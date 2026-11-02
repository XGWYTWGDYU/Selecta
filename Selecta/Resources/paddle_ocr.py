"""Local-only PaddleOCR adapter. Worker mode reuses the identical loaded model between screenshots."""
import argparse
import base64
import contextlib
import json
import logging
import os
from pathlib import Path
import socket
import sys

DETECTION = "PP-OCRv5_mobile_det"
RECOGNITION = "PP-OCRv5_mobile_rec"


def disable_network():
    class OfflineSocket(socket.socket):
        def connect(self, address):
            raise OSError("Selecta OCR runs offline; network access is disabled")
        def connect_ex(self, address):
            raise OSError("Selecta OCR runs offline; network access is disabled")
    socket.socket = OfflineSocket
    os.environ["HF_HUB_OFFLINE"] = "1"
    os.environ["PADDLE_PDX_DISABLE_MODEL_SOURCE_CHECK"] = "True"


def make_engine(root, prepare):
    from paddleocr import PaddleOCR
    options = dict(text_detection_model_name=DETECTION, text_recognition_model_name=RECOGNITION,
                   use_doc_orientation_classify=False, use_doc_unwarping=False,
                   use_textline_orientation=False, device="cpu", enable_mkldnn=False)
    if not prepare:
        detection = root / "official_models" / DETECTION
        recognition = root / "official_models" / RECOGNITION
        for model in (detection, recognition):
            if not (model / "inference.yml").is_file():
                raise RuntimeError("本地模型不完整，请运行 Scripts/setup-ocr.sh。")
        options.update(text_detection_model_dir=str(detection), text_recognition_model_dir=str(recognition))
    return PaddleOCR(**options)


def recognize(engine, image):
    texts = []
    for result in engine.predict(image):
        texts.extend(text for text in result.get("rec_texts", []) if text.strip())
    return "\n".join(texts)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--prepare", action="store_true")
    parser.add_argument("--worker", action="store_true")
    parser.add_argument("--image")
    parser.add_argument("--models", required=True)
    args = parser.parse_args()
    root = Path(args.models).expanduser().resolve()
    if args.image:
        args.image = str(Path(args.image).expanduser().resolve())
    support = Path.home() / "Library" / "Application Support" / "Selecta"
    cache = Path.home() / "Library" / "Caches" / "org.ra055814ae03f470d982b.selecta"
    cache.mkdir(parents=True, exist_ok=True)
    support.mkdir(parents=True, exist_ok=True)
    os.chdir(support)
    os.environ["HF_HOME"] = str(cache / "huggingface")
    os.environ["XDG_CACHE_HOME"] = str(cache / "inference")
    os.environ["MPLCONFIGDIR"] = str(cache / "matplotlib")
    os.environ["PADDLE_PDX_CACHE_HOME"] = str(root)
    os.environ.setdefault("PADDLE_PDX_MODEL_SOURCE", "bos")
    os.environ["FLAGS_use_mkldnn"] = "0"
    if not args.prepare:
        disable_network()
    logging.disable(logging.CRITICAL)
    try:
        # Reserve stdout for one-line results, including during model import and inference.
        with contextlib.redirect_stdout(sys.stderr):
            engine = make_engine(root, args.prepare)
        if args.prepare:
            print(f"Local OCR models ready: {root}")
            return 0
        jobs = sys.stdin if args.worker else [json.dumps({"image_path": args.image})]
        for line in jobs:
            job = json.loads(line)
            try:
                with contextlib.redirect_stdout(sys.stderr):
                    if args.worker:
                        import cv2
                        import numpy as np
                        image = cv2.imdecode(np.frombuffer(base64.b64decode(job["image"], validate=True), dtype=np.uint8), cv2.IMREAD_COLOR)
                        if image is None:
                            raise ValueError("Invalid image")
                    else:
                        image = job["image_path"]
                    result = {"text": recognize(engine, image)}
            except Exception:
                result = {"error": "PaddleOCR 识别失败，请检查图片和本地模型。"}
            if args.worker:
                result["id"] = job["id"]
            print(json.dumps(result, ensure_ascii=False), flush=True)
        return 0
    except Exception:
        print("PaddleOCR 初始化失败，请检查本地模型与 Python 环境。", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
