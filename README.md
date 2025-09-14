# Core ML Models Directory

This directory contains the Core ML models used for enhanced Apple Serial Scanner processing:

## Models

### SerialRegionDetector.mlpackage
- **Purpose**: Localizes serial number regions on device surfaces
- **Input**: 416x416 RGB image
- **Output**: Bounding boxes, confidences, and class predictions
- **Use case**: Replaces manual ROI detection with ML-based region localization

### SerialFormatClassifier.mlpackage  
- **Purpose**: Validates if detected text is a genuine Apple serial vs other text
- **Input**: Text features (128-dim) + Geometry features (8-dim)
- **Output**: Apple serial probability vs other text probability
- **Use case**: Reduces false positives from 12-character non-serial text

### CharacterDisambiguator.mlpackage
- **Purpose**: Resolves ambiguous characters (0/O, 1/I/L, 5/S) in context
- **Input**: 32x32 character image crops
- **Output**: Character probabilities for disambiguation
- **Use case**: Improves accuracy on engraved surfaces with unclear characters

## Model Format Notes

- Prefer `.mlpackage` format (compiled at build time)
- Fallback to `.mlmodel` format if needed
- Quantized variants (8-bit) available for performance optimization
- Models support CPU + Neural Engine compute units

## Integration

Models are loaded via `MLModelLoader.swift` with:
- Lazy loading and singleton pattern
- Warmup passes for optimal performance  
- Configurable compute units (Auto/NE+CPU/CPU-only)
- Memory management and cleanup

## Performance Targets

- Model loading: < 1.5s cold start
- Serial region detection: ~5-8 Hz
- Format classification: On-demand
- Character disambiguation: On-demand
- End-to-end latency: ≤ 600ms in good lighting
