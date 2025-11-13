#!/usr/bin/env python3
"""
Simple test script for WhisperX API
Usage: python test_api.py <audio_file>
"""

import requests
import sys
import json
from pathlib import Path

API_URL = "http://localhost:8000"


def test_health():
    """Test health endpoint"""
    print("🔍 Testing health endpoint...")
    response = requests.get(f"{API_URL}/health")
    print(f"Status: {response.status_code}")
    print(json.dumps(response.json(), indent=2))
    print()


def test_transcribe(audio_file, align=True, diarize=False):
    """Test transcription endpoint"""
    if not Path(audio_file).exists():
        print(f"❌ Error: File '{audio_file}' not found")
        return
    
    print(f"🎤 Transcribing: {audio_file}")
    print(f"   Alignment: {align}")
    print(f"   Diarization: {diarize}")
    print()
    
    with open(audio_file, 'rb') as f:
        files = {'file': f}
        params = {'align': align, 'diarize': diarize}
        
        print("⏳ Processing... (this may take a while)")
        response = requests.post(
            f"{API_URL}/transcribe/",
            files=files,
            params=params
        )
    
    print(f"Status: {response.status_code}")
    
    if response.status_code == 200:
        result = response.json()
        print("\n" + "="*60)
        print("TRANSCRIPTION RESULT")
        print("="*60)
        print(f"\n📝 Text:\n{result['text']}\n")
        print(f"🌍 Language: {result.get('language', 'N/A')}")
        print(f"📊 Segments: {len(result.get('segments', []))}")
        
        if result.get('word_segments'):
            print(f"💬 Words: {len(result['word_segments'])}")
        
        if result.get('diarization'):
            speakers = set(s.get('speaker') for s in result['diarization'] if s.get('speaker'))
            print(f"👥 Speakers detected: {len(speakers)}")
            print(f"   Speakers: {', '.join(sorted(speakers))}")
        
        print("\n" + "="*60)
        print("\n📄 Full JSON response saved to: result.json")
        with open('result.json', 'w') as f:
            json.dump(result, f, indent=2)
    else:
        print(f"❌ Error: {response.text}")


def main():
    print("="*60)
    print("WhisperX API Test Script")
    print("="*60)
    print()
    
    # Test health first
    try:
        test_health()
    except requests.exceptions.ConnectionError:
        print("❌ Error: Cannot connect to API. Is it running?")
        print("   Start the API with: docker-compose up")
        sys.exit(1)
    
    # Test transcription if audio file provided
    if len(sys.argv) < 2:
        print("ℹ️  Usage: python test_api.py <audio_file> [--diarize]")
        print("   Example: python test_api.py sample.mp3")
        print("   Example: python test_api.py sample.mp3 --diarize")
        sys.exit(0)
    
    audio_file = sys.argv[1]
    diarize = '--diarize' in sys.argv
    
    test_transcribe(audio_file, align=True, diarize=diarize)


if __name__ == "__main__":
    main()

