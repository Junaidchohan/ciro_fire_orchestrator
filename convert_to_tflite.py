import os
import shutil
from ultralytics import YOLO

def convert_and_copy():
    print("Loading YOLO model from backend/models/best.pt...")
    model = YOLO("backend/models/best.pt")
    
    print("Exporting to TFLite INT8 format...")
    # Export to TFLite format with INT8 precision
    model.export(format="tflite", int8=True, imgsz=320)
    
    # Path where ultralytics saves the exported model
    src_tflite = "backend/models/best_saved_model/best_int8.tflite"
    if not os.path.exists(src_tflite):
        src_tflite = "backend/models/best_int8.tflite"
        
    dest_dir = "app/assets/models"
    dest_tflite = os.path.join(dest_dir, "best_int8.tflite")
    
    print(f"Creating directory {dest_dir} if it doesn't exist...")
    os.makedirs(dest_dir, exist_ok=True)
    
    if os.path.exists(src_tflite):
        print(f"Copying {src_tflite} to {dest_tflite}...")
        shutil.copy2(src_tflite, dest_tflite)
        
        src_size = os.path.getsize(src_tflite) / (1024 * 1024)
        dest_size = os.path.getsize(dest_tflite) / (1024 * 1024)
        print("✅ Success!")
        print(f"Original size: {src_size:.2f} MB")
        print(f"Copied size: {dest_size:.2f} MB")
        print(f"Model successfully saved to {dest_tflite}")
    else:
        print(f"❌ Error: Could not find exported TFLite model at {src_tflite}")

if __name__ == "__main__":
    convert_and_copy()
