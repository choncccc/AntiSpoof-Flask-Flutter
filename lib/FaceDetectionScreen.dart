import 'dart:typed_data';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class FaceDetectionScreen extends StatefulWidget {
  @override
  _FaceDetectionScreenState createState() => _FaceDetectionScreenState();
  // HttpOverrides.global = MyHttpOverrides();
}

class MyHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback =
          (X509Certificate cert, String host, int port) => true;
  }
}

class _FaceDetectionScreenState extends State<FaceDetectionScreen> {
  late CameraController _cameraController;
  bool _isDetecting = false;
  List<Rect> _faceBoundingBoxes = [];

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
      ResolutionPreset.medium,
    );

    await _cameraController.initialize();
    _cameraController.startImageStream((CameraImage image) {
      if (!_isDetecting) {
        _isDetecting = true;
        processCameraImage(image);
      }
    });
    setState(() {});
  }

  Future<void> processCameraImage(CameraImage image) async {
    try {
      // Convert CameraImage to raw bytes
      final Uint8List bytes = concatenatePlanes(image.planes);

      // Send image to server
      final response = await http.post(
        Uri.parse('https://192.168.155.105:5000/detect'),
        headers: {'Content-Type': 'application/octet-stream'},
        body: bytes,
      );

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        setState(() {
          _faceBoundingBoxes = (result['faces'] as List).map((face) {
            final left = face['left'].toDouble();
            final top = face['top'].toDouble();
            final width = face['width'].toDouble();
            final height = face['height'].toDouble();
            return Rect.fromLTWH(left, top, width, height);
          }).toList();
        });
      } else {
        print('Error: ${response.body}');
      }
    } catch (e) {
      print('Error processing camera image: $e');
    } finally {
      _isDetecting = false;
    }
  }

  Uint8List concatenatePlanes(List<Plane> planes) {
    final WriteBuffer allBytes = WriteBuffer();
    for (Plane plane in planes) {
      allBytes.putUint8List(plane.bytes);
    }
    return allBytes.done().buffer.asUint8List();
  }

  @override
  void dispose() {
    _cameraController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Face Detection')),
      body: _cameraController.value.isInitialized
          ? Stack(
              children: [
                CameraPreview(_cameraController),
                ..._faceBoundingBoxes.map((rect) {
                  return Positioned(
                    left: rect.left,
                    top: rect.top,
                    width: rect.width,
                    height: rect.height,
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.red, width: 2.0),
                      ),
                    ),
                  );
                }).toList(),
              ],
            )
          : Center(child: CircularProgressIndicator()),
    );
  }
}
