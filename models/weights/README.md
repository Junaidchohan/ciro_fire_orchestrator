# models/weights/

Place your trained YOLOv8 weights file here as **`best.pt`**.

## How to obtain `best.pt`

### Option A – Use a pre-trained fire/smoke model
Download a community-trained fire-detection model:
```
pip install gdown
gdown <google-drive-file-id> -O best.pt
```

### Option B – Train your own (offline, not required for demo)
```bash
yolo train model=yolov8n.pt data=fire.yaml epochs=50 imgsz=640
# Copy runs/detect/train/weights/best.pt here
```

### Option C – Demo without weights (default)
If `best.pt` is absent the `YOLODetector` service automatically runs in
**mock mode**, returning plausible simulated detections so the full pipeline
can be demonstrated without a GPU or real weights file.

## Expected class names
The detector recognises classes named `fire`, `smoke`, and `flame`.
Any other classes returned by a custom model will be ignored.
