import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:http/http.dart' as http;
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

class FaceDetectionScreen extends StatefulWidget {
  @override
  _FaceDetectionScreenState createState() => _FaceDetectionScreenState();
}

class _FaceDetectionScreenState extends State<FaceDetectionScreen> {
  late CameraController _cameraController;
  Timer? _timer;
  String? displayMessage;
  late FaceDetector _faceDetector;

  @override
  void initState() {
    super.initState();
    initializeFaceDetector();
    initializeCamera();
  }

  Future<void> initializeFaceDetector() async {
    _faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        enableContours: true,
        enableLandmarks: true,
      ),
    );
  }

  Future<void> initializeCamera() async {
    final cameras = await availableCameras();
    _cameraController = CameraController(
      cameras.firstWhere(
        //(camera) => camera.lensDirection == CameraLensDirection.back,
        (camera) => camera.lensDirection == CameraLensDirection.front,
      ),
      ResolutionPreset.medium,
    );
    await _cameraController.initialize();
    await _cameraController.setFlashMode(FlashMode.off);
    startImageCaptureTimer();
    setState(() {});
  }

  void startImageCaptureTimer() {
    _timer = Timer.periodic(const Duration(seconds: 3), (timer) {
      captureAndSendImage();
    });
  }

  Future<void> captureAndSendImage() async {
    if (_cameraController.value.isInitialized &&
        !_cameraController.value.isTakingPicture) {
      try {
        final XFile file = await _cameraController.takePicture();
        final bytes = await file.readAsBytes();
        final base64Image = base64Encode(bytes);

        final inputImage = InputImage.fromBytes(
            bytes: bytes,
            metadata: InputImageMetadata(
              size: Size(_cameraController.value.previewSize!.width,
                  _cameraController.value.previewSize!.height),
              rotation: InputImageRotation.rotation0deg,
              format: InputImageFormat.yuv420,
              bytesPerRow:
                  bytes.length ~/ _cameraController.value.previewSize!.height,
            ));

        final List<Face> faces = await _faceDetector.processImage(inputImage);

        if (faces.isNotEmpty) {
          final face = faces.first;
          final leftEyeOpenProbability = face.leftEyeOpenProbability;
          final rightEyeOpenProbability = face.rightEyeOpenProbability;
          final smilingProbability = face.smilingProbability;

          if (leftEyeOpenProbability != null &&
              rightEyeOpenProbability != null &&
              smilingProbability != null) {
            if (leftEyeOpenProbability > 0.5 &&
                rightEyeOpenProbability > 0.5 &&
                smilingProbability > 0.5) {
              displayMessage = 'Live';
            } else {
              displayMessage = 'Spoof';
            }
          } else {
            displayMessage = 'No face detected';
          }
        } else {
          displayMessage = 'No face detected';
        }

        final response = await http.post(
          Uri.parse('http://192.168.155.105:5000/process_frame'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'image': base64Image}),
        );

        if (response.statusCode == 200) {
          final result = jsonDecode(response.body);
          setState(() {
            if (result['results'].isEmpty) {
              displayMessage = 'No face detected';
            } else {
              displayMessage = result['results'][0] ? 'Live' : 'Spoof';
            }
          });
        } else {
          print('Error: ${response.reasonPhrase}');
        }
      } catch (e) {
        print('Error capturing image: $e');
      }
    }
  }

  @override
  void dispose() {
    _cameraController.dispose();
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Face Detection')),
      body: Column(
        children: [
          if (_cameraController.value.isInitialized)
            CameraPreview(_cameraController),
          if (displayMessage != null)
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                'Detection Result: $displayMessage',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
        ],
      ),
    );
  }
}
