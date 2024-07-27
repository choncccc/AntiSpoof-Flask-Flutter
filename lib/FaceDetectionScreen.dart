import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:http/http.dart' as http;

class FaceDetectionScreen extends StatefulWidget {
  @override
  _FaceDetectionScreenState createState() => _FaceDetectionScreenState();
}

class _FaceDetectionScreenState extends State<FaceDetectionScreen> {
  late CameraController _cameraController;
  Timer? _timer;
  String? displayMessage;

  @override
  void initState() {
    super.initState();
    initializeCamera();
  }

  Future<void> initializeCamera() async {
    final cameras = await availableCameras();
    _cameraController = CameraController(
      cameras.firstWhere(
          (camera) => camera.lensDirection == CameraLensDirection.front),
      //(camera) => camera.lensDirection == CameraLensDirection.back),
      ResolutionPreset.medium,
    );
    await _cameraController.initialize();
    await _cameraController.setFlashMode(FlashMode.off);
    //captureAndSendImage();
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
        var base64Image = base64Encode(bytes);

        var response = await http.post(
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
