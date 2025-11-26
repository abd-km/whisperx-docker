# Set LD_LIBRARY_PATH to include PyTorch's bundled cuDNN libraries BEFORE importing torch/whisperx
# Per WhisperX troubleshooting guide: PyTorch comes bundled with cuDNN libraries
# that need to be in LD_LIBRARY_PATH for WhisperX to find them
# This is a backup in case the Dockerfile ENV doesn't work correctly
# IMPORTANT: This must run BEFORE importing torch/whisperx, as they load cuDNN during import
import os

# original = os.environ.get("LD_LIBRARY_PATH", "")
# # Confirmed path for Python 3.11 in pytorch/pytorch base image
# cudnn_path = "/opt/conda/lib/python3.11/site-packages/nvidia/cudnn/lib/"
# if os.path.isdir(cudnn_path):
#     if cudnn_path not in original:
#         os.environ['LD_LIBRARY_PATH'] = original + (":" if original else "") + cudnn_path
#         print(f"Added cuDNN path to LD_LIBRARY_PATH: {cudnn_path}")
# else:
#     print(f"Warning: cuDNN path not found at {cudnn_path}, using system libraries")

# # Now import libraries that depend on cuDNN

from fastapi import FastAPI, UploadFile, File, HTTPException
from fastapi.responses import JSONResponse
from pydantic import BaseModel
import whisperx
import torch
import gc
from typing import Optional
import nltk

# Download required NLTK data at startup
print("Downloading NLTK data...")
try:
    nltk.download('punkt_tab', quiet=True)
    print("NLTK data downloaded successfully!")
except Exception as e:
    print(f"Warning: Could not download NLTK data: {e}")

app = FastAPI(
    title="WhisperX API",
    description="WhisperX API with Transcription, Alignment, and Diarization",
    version="1.0.0"
)

# Configuration
DEVICE = "cuda" if torch.cuda.is_available() else "cpu"
COMPUTE_TYPE = "float16" if DEVICE == "cuda" else "int8"
BATCH_SIZE = 16
MODEL_NAME = os.getenv("WHISPER_MODEL", "large-v3")
HF_TOKEN = os.getenv("HF_TOKEN")  # Required for diarization

# Load WhisperX model once at startup
print(f"Loading WhisperX model '{MODEL_NAME}' on device: {DEVICE}")
model = whisperx.load_model(MODEL_NAME, DEVICE, compute_type=COMPUTE_TYPE)
print("Model loaded successfully!")


class TranscriptionResponse(BaseModel):
    """Response model for transcription"""
    text: str
    segments: list
    word_segments: Optional[list] = None
    diarization: Optional[list] = None
    language: Optional[str] = None


@app.get("/")
async def root():
    """Health check endpoint"""
    return {
        "status": "healthy",
        "service": "WhisperX API",
        "device": DEVICE,
        "model": MODEL_NAME,
        "features": ["transcription", "alignment", "diarization"]
    }


@app.get("/health")
async def health():
    """Detailed health check"""
    return {
        "status": "healthy",
        "cuda_available": torch.cuda.is_available(),
        "device": DEVICE,
        "model_loaded": model is not None,
        "diarization_available": HF_TOKEN is not None
    }


@app.post("/transcribe/", response_model=TranscriptionResponse)
async def transcribe(
    file: UploadFile = File(...),
    align: bool = True,
    diarize: bool = False,
    language: Optional[str] = None
):
    """
    Transcribe audio file with optional alignment and diarization
    
    Parameters:
    - file: Audio file (wav, mp3, m4a, etc.)
    - align: Enable word-level alignment (default: True)
    - diarize: Enable speaker diarization (default: False, requires HF_TOKEN)
    - language: Force specific language (optional, auto-detect if not provided)
    """
    
    # Validate file
    if not file.filename:
        raise HTTPException(status_code=400, detail="No file provided")
    
    # Check diarization requirements
    if diarize and not HF_TOKEN:
        raise HTTPException(
            status_code=400,
            detail="Diarization requires HF_TOKEN environment variable to be set"
        )
    
    audio_path = None
    
    try:
        # Save uploaded file temporarily
        audio_path = f"/tmp/{file.filename}"
        with open(audio_path, "wb") as f:
            f.write(await file.read())
        
        print(f"Processing file: {file.filename}")
        
        # 1. Transcribe with WhisperX
        print("Step 1: Transcribing audio...")
        audio = whisperx.load_audio(audio_path)
        result = model.transcribe(
            audio,
            batch_size=BATCH_SIZE,
            language=language
        )
        
        detected_language = result.get("language", "unknown")
        print(f"Detected language: {detected_language}")
        
        # Construct full text from segments if not present
        full_text = result.get("text", "")
        if not full_text and "segments" in result:
            full_text = " ".join([seg.get("text", "").strip() for seg in result["segments"]])
        
        # Prepare response
        response_data = {
            "text": full_text,
            "segments": result.get("segments", []),
            "language": detected_language
        }
        
        # 2. Align whisper output (word-level timestamps)
        if align:
            print("Step 2: Aligning transcription...")
            try:
                model_a, metadata = whisperx.load_align_model(
                    language_code=detected_language,
                    device=DEVICE
                )
                result_aligned = whisperx.align(
                    result["segments"],
                    model_a,
                    metadata,
                    audio,
                    DEVICE,
                    return_char_alignments=False
                )
                
                response_data["word_segments"] = result_aligned.get("word_segments", [])
                response_data["segments"] = result_aligned.get("segments", result["segments"])
                
                # Clear alignment model from memory
                del model_a
                gc.collect()
                torch.cuda.empty_cache() if DEVICE == "cuda" else None
                
                print("Alignment completed!")
            except Exception as e:
                print(f"Alignment warning: {str(e)}")
                response_data["word_segments"] = []
        
        # 3. Diarization (speaker identification)
        if diarize:
            print("Step 3: Running diarization...")
            try:
                diarize_model = whisperx.DiarizationPipeline(
                    use_auth_token=HF_TOKEN,
                    device=DEVICE
                )
                
                diarize_segments = diarize_model(audio)
                
                # Assign speakers to segments
                result_diarized = whisperx.assign_word_speakers(
                    diarize_segments,
                    result_aligned if align else result
                )
                
                response_data["diarization"] = result_diarized.get("segments", [])
                response_data["segments"] = result_diarized.get("segments", response_data["segments"])
                
                # Clear diarization model from memory
                del diarize_model
                gc.collect()
                torch.cuda.empty_cache() if DEVICE == "cuda" else None
                
                print("Diarization completed!")
            except Exception as e:
                print(f"Diarization error: {str(e)}")
                raise HTTPException(
                    status_code=500,
                    detail=f"Diarization failed: {str(e)}"
                )
        
        print(f"Successfully processed: {file.filename}")
        return JSONResponse(content=response_data)
    
    except Exception as e:
        print(f"Error processing file: {str(e)}")
        raise HTTPException(status_code=500, detail=f"Processing failed: {str(e)}")
    
    finally:
        # Cleanup temporary file
        if audio_path and os.path.exists(audio_path):
            try:
                os.remove(audio_path)
                print(f"Cleaned up temporary file: {audio_path}")
            except Exception as e:
                print(f"Warning: Could not remove temporary file: {e}")


@app.post("/transcribe/batch/")
async def transcribe_batch(
    files: list[UploadFile] = File(...),
    align: bool = True,
    diarize: bool = False,
    language: Optional[str] = None
):
    """
    Transcribe multiple audio files at once
    """
    results = []
    
    for file in files:
        try:
            result = await transcribe(file, align, diarize, language)
            results.append({
                "filename": file.filename,
                "status": "success",
                "result": result
            })
        except Exception as e:
            results.append({
                "filename": file.filename,
                "status": "error",
                "error": str(e)
            })
    
    return {"results": results}


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)

