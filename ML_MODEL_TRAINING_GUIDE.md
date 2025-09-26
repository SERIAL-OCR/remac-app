# Core ML Model Training Guide for Apple Serial Scanner

## Overview
This document outlines the requirements and training process for the three Core ML models used in the Apple Serial Scanner application.

## Models Overview

### 1. CharacterDisambiguator.mlmodel
**Purpose**: Resolves ambiguous characters in serial numbers (0/O, 1/I/L, 5/S, 8/B)

**Current Status**: ✅ Placeholder model with improved weight distribution
**Training Required**: ⚠️ **CRITICAL** - Needs training on Apple serial character data

**Input**: 32x32x3 character image
**Output**: 36-class classification (0-9, A-Z) with confidence scores

**Training Data Requirements**:
- 10,000+ cropped character images from Apple serial numbers
- Balanced dataset across all 36 character classes
- Various fonts, lighting conditions, and image qualities
- Augmented data (rotation, noise, blur) for robustness

**Training Process**:
1. Collect Apple serial number images
2. Extract individual characters using OCR bounding boxes
3. Label characters manually or semi-automatically
4. Augment dataset with transformations
5. Train CNN classifier using Create ML or PyTorch
6. Convert to Core ML format

### 2. SerialFormatClassifier.mlmodel
**Purpose**: Classifies text regions as Apple serial numbers vs other text

**Current Status**: ✅ Placeholder model with improved weight distribution
**Training Required**: ⚠️ **CRITICAL** - Needs training on text classification data

**Input**: 
- Text features (128-dimensional embedding)
- Geometry features (8-dimensional: position, size, aspect ratio, etc.)

**Output**: Single confidence score (0.0-1.0) for Apple serial probability

**Training Data Requirements**:
- 5,000+ text regions from Apple devices (positive examples)
- 5,000+ text regions from other sources (negative examples)
- Various text types: model numbers, IMEI, serial numbers, barcodes, etc.
- Different device types and generations

**Training Process**:
1. Extract text features using pre-trained text embedding model
2. Extract geometry features (position, size, aspect ratio, etc.)
3. Create balanced positive/negative dataset
4. Train neural network regressor
5. Validate on held-out test set
6. Convert to Core ML format

### 3. SerialRegionDetector.mlmodel
**Purpose**: Detects and localizes serial number regions in images

**Current Status**: ✅ Placeholder model with improved weight distribution
**Training Required**: ⚠️ **CRITICAL** - Needs training on object detection data

**Input**: 416x416x3 full device image
**Output**: 
- Bounding boxes (5 detections max)
- Confidence scores
- Class indices (0 = serial_region)

**Training Data Requirements**:
- 2,000+ Apple device images with serial number annotations
- Bounding box coordinates for serial number locations
- Various device types, angles, lighting conditions
- Different serial number positions and orientations

**Training Process**:
1. Collect Apple device images
2. Annotate serial number bounding boxes
3. Augment with transformations (rotation, scaling, lighting)
4. Train YOLO-style object detector
5. Convert to Core ML format

## Current Model Status

### ✅ What's Working
- Model files exist and are properly structured
- App can load models without crashing
- Input/output specifications are correct
- Model loading and warmup code is implemented

### ⚠️ What Needs Training
- **All model weights are placeholder values** (0.1, 0.2, etc.)
- **No actual learned parameters** from real data
- **Predictions will be essentially random** until trained

## Immediate Actions Required

### 1. Data Collection (Priority 1)
```
CharacterDisambiguator:
- Collect 10,000+ Apple serial character images
- Label each character (0-9, A-Z)
- Ensure balanced class distribution

SerialFormatClassifier:
- Collect 5,000+ Apple serial text regions
- Collect 5,000+ non-serial text regions
- Extract text and geometry features

SerialRegionDetector:
- Collect 2,000+ Apple device images
- Annotate serial number bounding boxes
- Include various device types and angles
```

### 2. Training Infrastructure
- Set up Create ML or PyTorch training environment
- Implement data preprocessing pipelines
- Create model conversion scripts
- Set up validation and testing procedures

### 3. Model Validation
- Test models on held-out validation set
- Measure accuracy, precision, recall
- Optimize for mobile deployment (size, speed)
- A/B test different model architectures

## Expected Performance After Training

### CharacterDisambiguator
- **Target Accuracy**: >95% on ambiguous characters
- **Inference Time**: <10ms per character
- **Model Size**: <5MB

### SerialFormatClassifier
- **Target Accuracy**: >90% classification accuracy
- **Inference Time**: <5ms per text region
- **Model Size**: <2MB

### SerialRegionDetector
- **Target mAP**: >0.8 for serial region detection
- **Inference Time**: <50ms per image
- **Model Size**: <10MB

## Training Timeline

### Phase 1: Data Collection (2-3 weeks)
- Collect and annotate training data
- Set up data preprocessing pipelines
- Create validation/test splits

### Phase 2: Model Training (1-2 weeks)
- Train each model on collected data
- Hyperparameter tuning
- Model architecture optimization

### Phase 3: Integration & Testing (1 week)
- Convert trained models to Core ML
- Integrate with existing app code
- Performance testing and optimization

## Notes
- Current placeholder models will prevent app crashes
- Models will work but with poor accuracy until trained
- Consider using pre-trained models as starting points
- Implement fallback mechanisms for low-confidence predictions

## Next Steps
1. **Immediate**: Use current placeholder models for development
2. **Short-term**: Begin data collection for all three models
3. **Medium-term**: Train and validate models on real data
4. **Long-term**: Continuously improve models with more data