"""Local-only PP-OCRv5 adapter. Worker mode reuses the loaded model between screenshots.

The same Baidu PP-OCRv5 weights run on ONNX Runtime in fp32. Text detection runs on the Apple GPU
through Core ML (static, bucketed input shapes, compiled once and cached on disk). Text recognition
stays on the CPU, one line per call across all cores: Core ML needs fixed shapes, and padding lines
to fixed widths measurably changes PP-OCRv5's recognition output, while unpadded lines reproduce
PaddlePaddle exactly. Environments installed before the ONNX export existed keep using PaddlePaddle.
"""
import argparse
import base64
import collections
from concurrent.futures import ThreadPoolExecutor
import contextlib
import json
import logging
import math
import os
from pathlib import Path
import socket
import sys

DETECTION = "PP-OCRv5_mobile_det"
RECOGNITION = "PP-OCRv5_mobile_rec"
ONNX_FORMAT = "1"  # Bump when the exported graph rewrite changes.

# PaddleX OCR pipeline defaults for PP-OCRv5 (paddlex/configs/pipelines/OCR.yaml).
DET_LIMIT_SIDE, DET_MAX_SIDE = 64, 4000
DET_THRESH, DET_BOX_THRESH, DET_UNCLIP = 0.3, 0.6, 1.5
REC_HEIGHT, REC_MIN_WIDTH, REC_MAX_WIDTH = 48, 320, 3200


def disable_network():
    class OfflineSocket(socket.socket):
        def connect(self, address):
            raise OSError("Selecta OCR runs offline; network access is disabled")
        def connect_ex(self, address):
            raise OSError("Selecta OCR runs offline; network access is disabled")
    socket.socket = OfflineSocket
    os.environ["HF_HUB_OFFLINE"] = "1"
    os.environ["PADDLE_PDX_DISABLE_MODEL_SOURCE_CHECK"] = "True"


def model_dirs(root):
    detection = root / "official_models" / DETECTION
    recognition = root / "official_models" / RECOGNITION
    for model in (detection, recognition):
        if not (model / "inference.yml").is_file():
            raise RuntimeError("本地模型不完整，请在 Selecta 设置 → 离线 OCR 中重新安装。")
    return detection, recognition


def onnx_file(root, name):
    return root / "onnx" / f"{name}.v{ONNX_FORMAT}.onnx"


# ---------------------------------------------------------------- ONNX export (install time)

def coreml_friendly(model):
    """Expand HardSwish/HardSigmoid into Mul/Add/Clip, which Core ML executes natively.

    Mathematically identical; without it ONNX Runtime splits the graph into ~30 CPU/Core ML
    partitions and the GPU never pays off.
    """
    import numpy as np
    from onnx import helper, numpy_helper
    nodes, constants = [], []

    def constant(value):
        name = f"_selecta_const_{len(constants)}"
        constants.append(numpy_helper.from_array(np.array(value, np.float32), name))
        return name

    zero, one = constant(0.0), constant(1.0)

    def hard_sigmoid(x, out, alpha, beta):
        scaled, shifted = out + "_selecta_scaled", out + "_selecta_shifted"
        nodes.extend([helper.make_node("Mul", [x, constant(alpha)], [scaled]),
                      helper.make_node("Add", [scaled, constant(beta)], [shifted]),
                      helper.make_node("Clip", [shifted, zero, one], [out])])

    for node in model.graph.node:
        if node.op_type == "HardSwish":
            gate = node.output[0] + "_selecta_gate"
            hard_sigmoid(node.input[0], gate, 1 / 6, 0.5)
            nodes.append(helper.make_node("Mul", [node.input[0], gate], [node.output[0]]))
        elif node.op_type == "HardSigmoid":
            attributes = {a.name: helper.get_attribute_value(a) for a in node.attribute}
            hard_sigmoid(node.input[0], node.output[0], attributes.get("alpha", 0.2), attributes.get("beta", 0.5))
        else:
            nodes.append(node)
    del model.graph.node[:]
    model.graph.node.extend(nodes)
    model.graph.initializer.extend(constants)
    return model


def export_onnx(root):
    import onnx
    import paddle2onnx
    directory = root / "onnx"
    directory.mkdir(parents=True, exist_ok=True)
    for name, source in zip((DETECTION, RECOGNITION), model_dirs(root)):
        target = onnx_file(root, name)
        if target.is_file():
            continue
        raw = directory / f"{name}.export.onnx"
        paddle2onnx.export(str(source / "inference.json"), str(source / "inference.pdiparams"),
                           save_file=str(raw), opset_version=14)
        model = coreml_friendly(onnx.load(str(raw)))
        onnx.checker.check_model(model)
        partial = directory / f"{name}.partial.onnx"
        onnx.save(model, str(partial))
        os.replace(partial, target)
        raw.unlink(missing_ok=True)
    for stale in directory.glob("*.onnx"):
        if stale not in (onnx_file(root, DETECTION), onnx_file(root, RECOGNITION)):
            stale.unlink(missing_ok=True)


# ---------------------------------------------------------------- ONNX Runtime engine

class OnnxEngine:
    def __init__(self, root, cache):
        import numpy as np
        import cv2
        import onnx
        import onnxruntime as ort
        import pyclipper
        import yaml
        self.np, self.cv2, self.onnx, self.ort, self.pyclipper = np, cv2, onnx, ort, pyclipper
        _, recognition = model_dirs(root)
        with open(recognition / "inference.yml", encoding="utf-8") as file:
            characters = yaml.safe_load(file)["PostProcess"]["character_dict"]
        self.characters = ["blank"] + list(characters) + [" "]
        self.models = {kind: onnx.load(str(onnx_file(root, name))) for kind, name in (("det", DETECTION), ("rec", RECOGNITION))}
        self.cache = cache / "coreml"
        self.cache.mkdir(parents=True, exist_ok=True)
        self.gpu = "CoreMLExecutionProvider" in ort.get_available_providers()
        self.sessions = collections.OrderedDict()
        # Single-threaded sessions run in parallel; per-line work is too small to split across cores.
        self.workers = max(1, min(8, os.cpu_count() or 4))
        self.pool = ThreadPoolExecutor(self.workers)
        options = self.options()
        options.intra_op_num_threads = 1
        self.recognizer = ort.InferenceSession(self.models["rec"].SerializeToString(), options, providers=["CPUExecutionProvider"])
        self.mean = np.array([0.485, 0.456, 0.406], np.float32)
        self.std = np.array([0.229, 0.224, 0.225], np.float32)

    @property
    def label(self):
        return "PaddleOCR · PP-OCRv5（GPU 检测 · 多核识别）" if self.gpu else "PaddleOCR · PP-OCRv5（ONNX · 多核 CPU）"

    def options(self):
        options = self.ort.SessionOptions()
        options.log_severity_level = 3
        options.graph_optimization_level = self.ort.GraphOptimizationLevel.ORT_ENABLE_ALL
        return options

    def session(self, kind, shape):
        """Core ML needs static shapes to run the whole graph on the GPU; compiled models are cached."""
        key = (kind, tuple(shape)) if self.gpu else (kind, None)
        if key in self.sessions:
            self.sessions.move_to_end(key)
            return self.sessions[key]
        model = self.models[kind]
        if self.gpu:
            model = self.onnx.ModelProto()
            model.CopyFrom(self.models[kind])
            for dim, value in zip(model.graph.input[0].type.tensor_type.shape.dim, shape):
                dim.ClearField("dim_param")
                dim.dim_value = value
            for output in model.graph.output:
                for dim in output.type.tensor_type.shape.dim:
                    dim.ClearField("dim_param")
                    dim.ClearField("dim_value")
            entry = model.metadata_props.add()
            entry.key = "COREML_CACHE_KEY"
            entry.value = f"selecta{kind}v{ONNX_FORMAT}" + "x".join(map(str, shape))
            providers = [("CoreMLExecutionProvider", {"ModelFormat": "MLProgram", "MLComputeUnits": "CPUAndGPU",
                                                      "RequireStaticInputShapes": "1", "ModelCacheDirectory": str(self.cache)}),
                         "CPUExecutionProvider"]
        else:
            providers = ["CPUExecutionProvider"]
        session = self.ort.InferenceSession(model.SerializeToString(), self.options(), providers=providers)
        self.sessions[key] = session
        while len(self.sessions) > 16:
            self.sessions.popitem(last=False)
        return session

    def run(self, kind, x):
        try:
            return self.session(kind, x.shape).run(None, {"x": x})[0]
        except Exception:
            if not self.gpu:
                raise
            # Core ML unavailable or failed on this Mac: keep working on the CPU.
            self.gpu = False
            self.sessions.clear()
            return self.session(kind, x.shape).run(None, {"x": x})[0]

    def warm_up(self):
        np = self.np
        self.recognizer.run(None, {"x": np.zeros((1, 3, REC_HEIGHT, REC_MIN_WIDTH), np.float32)})
        for shape in ((256, 512), (256, 1024), (512, 1024), (1024, 1536)):
            self.run("det", np.zeros((1, 3) + shape, np.float32))

    # Detection: PaddleX DetResizeForTest (limit_type=min) + DBPostProcess (quad, fast score).
    @staticmethod
    def bucket(size):
        step = 256 if size <= 1024 else 512
        return int(math.ceil(size / step) * step)

    def detect(self, image):
        np, cv2 = self.np, self.cv2
        height, width = image.shape[:2]
        if height + width < 64:
            padded = np.zeros((max(32, height), max(32, width), 3), np.uint8)
            padded[:height, :width] = image
            image = padded
            height, width = image.shape[:2]
        ratio = DET_LIMIT_SIDE / min(height, width) if min(height, width) < DET_LIMIT_SIDE else 1.0
        resized_h, resized_w = int(height * ratio), int(width * ratio)
        if max(resized_h, resized_w) > DET_MAX_SIDE:
            scale = DET_MAX_SIDE / max(resized_h, resized_w)
            resized_h, resized_w = int(resized_h * scale), int(resized_w * scale)
        resized_h = max(int(round(resized_h / 32) * 32), 32)
        resized_w = max(int(round(resized_w / 32) * 32), 32)
        if (resized_h, resized_w) != (height, width):
            image = cv2.resize(image, (resized_w, resized_h))
        normalized = (image.astype(np.float32) / 255.0 - self.mean) / self.std
        if self.gpu:
            x = np.zeros((1, 3, self.bucket(resized_h), self.bucket(resized_w)), np.float32)
        else:
            x = np.zeros((1, 3, resized_h, resized_w), np.float32)
        x[0, :, :resized_h, :resized_w] = normalized.transpose(2, 0, 1)
        prediction = self.run("det", x)[0, 0, :resized_h, :resized_w]
        return self.boxes(prediction, width, height)

    @staticmethod
    def mini_box(contour, cv2, np):
        rect = cv2.minAreaRect(contour)
        points = sorted(list(cv2.boxPoints(rect)), key=lambda point: point[0])
        a, d = (0, 1) if points[1][1] > points[0][1] else (1, 0)
        b, c = (2, 3) if points[3][1] > points[2][1] else (3, 2)
        return np.array([points[a], points[b], points[c], points[d]]), min(rect[1])

    def box_score(self, bitmap, box):
        np, cv2 = self.np, self.cv2
        height, width = bitmap.shape
        box = box.copy()
        xmin = max(0, min(math.floor(box[:, 0].min()), width - 1))
        xmax = max(0, min(math.ceil(box[:, 0].max()), width - 1))
        ymin = max(0, min(math.floor(box[:, 1].min()), height - 1))
        ymax = max(0, min(math.ceil(box[:, 1].max()), height - 1))
        mask = np.zeros((ymax - ymin + 1, xmax - xmin + 1), np.uint8)
        box[:, 0] -= xmin
        box[:, 1] -= ymin
        cv2.fillPoly(mask, box.reshape(1, -1, 2).astype(np.int32), 1)
        return cv2.mean(bitmap[ymin:ymax + 1, xmin:xmax + 1], mask)[0]

    def boxes(self, prediction, dest_width, dest_height):
        np, cv2, pyclipper = self.np, self.cv2, self.pyclipper
        bitmap = prediction > DET_THRESH
        height, width = bitmap.shape
        contours, _ = cv2.findContours((bitmap * 255).astype(np.uint8), cv2.RETR_LIST, cv2.CHAIN_APPROX_SIMPLE)
        boxes = []
        for contour in contours[:1000]:
            points, side = self.mini_box(contour, cv2, np)
            if side < 3 or self.box_score(prediction, points) < DET_BOX_THRESH:
                continue
            distance = cv2.contourArea(points) * DET_UNCLIP / cv2.arcLength(points, True)
            offset = pyclipper.PyclipperOffset()
            offset.AddPath(points, pyclipper.JT_ROUND, pyclipper.ET_CLOSEDPOLYGON)
            expanded = offset.Execute(distance)
            if not expanded:
                continue
            box, side = self.mini_box(np.array(expanded[0]).reshape(-1, 1, 2), cv2, np)
            if side < 5:
                continue
            box[:, 0] = np.clip(np.round(box[:, 0] * dest_width / width), 0, dest_width)
            box[:, 1] = np.clip(np.round(box[:, 1] * dest_height / height), 0, dest_height)
            boxes.append(box.astype(np.int16))
        boxes.sort(key=lambda box: (box[0][1], box[0][0]))
        for i in range(len(boxes) - 1):
            for j in range(i, -1, -1):
                if abs(boxes[j + 1][0][1] - boxes[j][0][1]) < 10 and boxes[j + 1][0][0] < boxes[j][0][0]:
                    boxes[j], boxes[j + 1] = boxes[j + 1], boxes[j]
                else:
                    break
        return boxes

    def crop(self, image, points):
        np, cv2 = self.np, self.cv2
        box, _ = self.mini_box(np.array(points).astype(np.int32), cv2, np)
        box = box.astype(np.float32)
        crop_width = int(max(np.linalg.norm(box[0] - box[1]), np.linalg.norm(box[2] - box[3])))
        crop_height = int(max(np.linalg.norm(box[0] - box[3]), np.linalg.norm(box[1] - box[2])))
        if crop_width <= 0 or crop_height <= 0:
            return None
        matrix = cv2.getPerspectiveTransform(box, np.float32([[0, 0], [crop_width, 0], [crop_width, crop_height], [0, crop_height]]))
        cropped = cv2.warpPerspective(image, matrix, (crop_width, crop_height), borderMode=cv2.BORDER_REPLICATE, flags=cv2.INTER_CUBIC)
        if cropped.shape[0] / cropped.shape[1] >= 1.5:
            cropped = np.rot90(cropped)
        return cropped

    # Recognition: PaddleX OCRReisizeNormImg + CTCLabelDecode with batch size 1 (no cross-line padding).
    def recognize_line(self, crop):
        np, cv2 = self.np, self.cv2
        resized_width = min(REC_MAX_WIDTH, int(math.ceil(REC_HEIGHT * crop.shape[1] / crop.shape[0])))
        x = np.zeros((1, 3, REC_HEIGHT, max(REC_MIN_WIDTH, resized_width)), np.float32)
        line = cv2.resize(crop, (resized_width, REC_HEIGHT)).astype(np.float32).transpose(2, 0, 1) / 255.0
        x[0, :, :, :resized_width] = (line - 0.5) / 0.5
        sequence = self.recognizer.run(None, {"x": x})[0][0].argmax(-1)
        keep = np.ones(len(sequence), bool)
        keep[1:] = sequence[1:] != sequence[:-1]
        keep &= sequence != 0
        return "".join(self.characters[token] for token in sequence[keep])

    def recognize_lines(self, crops):
        # Longest lines first so the slowest work starts immediately.
        order = sorted(range(len(crops)), key=lambda i: -crops[i].shape[1] / crops[i].shape[0])
        texts = [""] * len(crops)
        for i, text in zip(order, self.pool.map(lambda i: self.recognize_line(crops[i]), order)):
            texts[i] = text
        return texts

    def __call__(self, image):
        crops = [crop for crop in (self.crop(image, box) for box in self.detect(image)) if crop is not None and crop.size]
        return "\n".join(text for text in self.recognize_lines(crops) if text.strip())


# ---------------------------------------------------------------- PaddlePaddle engine (legacy environments)

class PaddleEngine:
    label = "PaddleOCR · PP-OCRv5（本机 CPU）"

    def __init__(self, root, prepare):
        from paddleocr import PaddleOCR
        options = dict(text_detection_model_name=DETECTION, text_recognition_model_name=RECOGNITION,
                       use_doc_orientation_classify=False, use_doc_unwarping=False,
                       use_textline_orientation=False, device="cpu", enable_mkldnn=False)
        if not prepare:
            detection, recognition = model_dirs(root)
            options.update(text_detection_model_dir=str(detection), text_recognition_model_dir=str(recognition))
        self.engine = PaddleOCR(**options)

    def __call__(self, image):
        texts = []
        for result in self.engine.predict(image):
            texts.extend(text for text in result.get("rec_texts", []) if text.strip())
        return "\n".join(texts)


def make_engine(root, cache):
    try:
        import onnxruntime  # noqa: F401
        available = all(onnx_file(root, name).is_file() for name in (DETECTION, RECOGNITION))
    except ImportError:
        available = False
    if available:
        return OnnxEngine(root, cache)
    return PaddleEngine(root, prepare=False)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--prepare", action="store_true")
    parser.add_argument("--worker", action="store_true")
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--image")
    parser.add_argument("--models", required=True)
    args = parser.parse_args()
    root = Path(args.models).expanduser().resolve()
    if args.image:
        args.image = str(Path(args.image).expanduser().resolve())
    support = Path(os.environ.get("SELECTA_SUPPORT_DIR", Path.home() / "Library" / "Application Support" / "Selecta"))
    cache = Path(os.environ.get("SELECTA_CACHE_DIR", Path.home() / "Library" / "Caches" / "org.ra055814ae03f470d982b.selecta"))
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
            if args.prepare:
                PaddleEngine(root, prepare=True)
                try:
                    export_onnx(root)
                except Exception as error:  # PaddlePaddle remains usable without the accelerated models.
                    print(f"ONNX export failed, using PaddlePaddle: {error}", file=sys.stderr)
            else:
                engine = make_engine(root, cache)
                if args.check and isinstance(engine, OnnxEngine):
                    engine.warm_up()  # Compile the Core ML models now rather than on the first screenshot.
        if args.check:
            return 0
        if args.prepare:
            print(f"Local OCR models ready: {root}")
            return 0
        import cv2
        import numpy as np
        jobs = sys.stdin if args.worker else [json.dumps({"image_path": args.image})]
        for line in jobs:
            job = json.loads(line)
            try:
                with contextlib.redirect_stdout(sys.stderr):
                    if args.worker:
                        data = np.frombuffer(base64.b64decode(job["image"], validate=True), dtype=np.uint8)
                        image = cv2.imdecode(data, cv2.IMREAD_COLOR)
                    else:
                        image = cv2.imread(job["image_path"], cv2.IMREAD_COLOR)
                    if image is None:
                        raise ValueError("Invalid image")
                    result = {"text": engine(image), "engine": engine.label}
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
