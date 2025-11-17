#!/usr/bin/env python3
"""
Direct WhisperX test script (no API)
Usage: python test_whisperx_direct.py <audio_file> [--hf-token TOKEN]
"""

import sys
import os
import whisperx
import gc
import torch
from whisperx.diarize import DiarizationPipeline

# Configuration
device = "cuda" if torch.cuda.is_available() else "cpu"
batch_size = 16
compute_type = "float16" if device == "cuda" else "int8"

print(f"🔧 Device: {device}")
print(f"🔧 Compute type: {compute_type}")
print("")

# Get audio file from command line
if len(sys.argv) < 2:
    print("❌ Usage: python test_whisperx_direct.py <audio_file> [--hf-token TOKEN]")
    sys.exit(1)

audio_file = sys.argv[1]

# Get HF token
hf_token = os.getenv("HF_TOKEN")
if "--hf-token" in sys.argv:
    idx = sys.argv.index("--hf-token")
    hf_token = sys.argv[idx + 1]

if not hf_token:
    print("⚠️  Warning: No HF_TOKEN provided. Diarization will be skipped.")
    print("   Set with: export HF_TOKEN=your_token")
    print("")

# Check if file exists
if not os.path.exists(audio_file):
    print(f"❌ Error: File '{audio_file}' not found")
    sys.exit(1)

print(f"📁 Audio file: {audio_file}")
print("="*60)
print("")

try:
    # 1. Transcribe with original whisper (batched)
    print("📝 Step 1: Transcribing audio...")
    model = whisperx.load_model("large-v3", device, compute_type=compute_type)
    
    audio = whisperx.load_audio(audio_file)
    result = model.transcribe(audio, batch_size=batch_size)
    
    print(f"✅ Transcription complete!")
    print(f"   Language detected: {result['language']}")
    print(f"   Number of segments: {len(result['segments'])}")
    print("")
    print("📄 Raw segments (before alignment):")
    for i, seg in enumerate(result["segments"][:3]):  # Show first 3
        print(f"   [{seg['start']:.2f}s - {seg['end']:.2f}s] {seg['text']}")
    if len(result["segments"]) > 3:
        print(f"   ... and {len(result['segments']) - 3} more")
    print("")
    
    # 2. Align whisper output
    print("🎯 Step 2: Aligning transcription...")
    model_a, metadata = whisperx.load_align_model(
        language_code=result["language"],
        device=device
    )
    result_aligned = whisperx.align(
        result["segments"],
        model_a,
        metadata,
        audio,
        device,
        return_char_alignments=False
    )
    
    print("✅ Alignment complete!")
    if "word_segments" in result_aligned:
        print(f"   Word-level timestamps: {len(result_aligned['word_segments'])} words")
        print("")
        print("📄 Word segments (first 10 words):")
        for word in result_aligned["word_segments"][:10]:
            print(f"   [{word['start']:.2f}s - {word['end']:.2f}s] {word['word']} (score: {word.get('score', 0):.2f})")
        if len(result_aligned["word_segments"]) > 10:
            print(f"   ... and {len(result_aligned['word_segments']) - 10} more words")
    print("")
    
    # Delete model if low on GPU resources
    del model_a
    gc.collect()
    if device == "cuda":
        torch.cuda.empty_cache()
    
    # 3. Assign speaker labels (if HF token provided)
    if hf_token:
        print("👥 Step 3: Running speaker diarization...")
        diarize_model = DiarizationPipeline(
            use_auth_token=hf_token,
            device=device
        )
        
        diarize_segments = diarize_model(audio)
        result_final = whisperx.assign_word_speakers(diarize_segments, result_aligned)
        
        # Count unique speakers
        speakers = set()
        for seg in result_final["segments"]:
            if "speaker" in seg:
                speakers.add(seg["speaker"])
        
        print("✅ Diarization complete!")
        print(f"   Speakers detected: {len(speakers)} ({', '.join(sorted(speakers))})")
        print("")
        print("📄 Final segments with speakers:")
        for seg in result_final["segments"]:
            speaker = seg.get("speaker", "UNKNOWN")
            print(f"   [{seg['start']:.2f}s - {seg['end']:.2f}s] [{speaker}] {seg['text']}")
        
        del diarize_model
        gc.collect()
        if device == "cuda":
            torch.cuda.empty_cache()
    else:
        result_final = result_aligned
        print("⏭️  Step 3: Skipped (no HF_TOKEN)")
        print("")
    
    # Summary
    print("")
    print("="*60)
    print("📊 FINAL RESULT")
    print("="*60)
    print("")
    print(f"🌍 Language: {result['language']}")
    print(f"📝 Full Text:")
    print(f"   {result['text']}")
    print("")
    print(f"📊 Statistics:")
    print(f"   - Total segments: {len(result_final['segments'])}")
    if "word_segments" in result_final:
        print(f"   - Total words: {len(result_final['word_segments'])}")
    if hf_token:
        print(f"   - Speakers: {len(speakers)}")
    print("")
    
    # Save to file
    import json
    output_file = f"{audio_file}.json"
    with open(output_file, "w") as f:
        json.dump(result_final, f, indent=2)
    print(f"💾 Full result saved to: {output_file}")
    
except Exception as e:
    print(f"❌ Error: {str(e)}")
    import traceback
    traceback.print_exc()
    sys.exit(1)
finally:
    # Cleanup
    if device == "cuda":
        torch.cuda.empty_cache()

print("")
print("✅ Done!")

