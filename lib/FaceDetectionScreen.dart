import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class FaceDetectionScreen extends StatefulWidget {
  @override
  _FaceDetectionScreenState createState() => _FaceDetectionScreenState();
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
      final Uint8List bytes = concatenatePlanes(image.planes, image.width, image.height);

      if (bytes.isEmpty) {
        print("No image data captured");
        return;
      }

      // Send image to server
      final response = await http.post(
        Uri.parse('http://192.168.100.7:5000/process_frame'),
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

  Uint8List concatenatePlanes(List<Plane> planes, int width, int height) {
    final int imageSize = width * height * 3 ~/ 2;
    final Uint8List bytes = Uint8List(imageSize);
    int offset = 0;

    for (Plane plane in planes) {
      bytes.setRange(offset, offset + plane.bytes.length, plane.bytes);
      offset += plane.bytes.length;
    }

    return bytes;
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
              fit: StackFit.expand,
              children: [
                CameraPreview(_cameraController),
                CustomPaint(
                  painter: FacePainter(_faceBoundingBoxes),
                ),
              ],
            )
          : Center(child: CircularProgressIndicator()),
    );
  }
}

class FacePainter extends CustomPainter {
  final List<Rect> faceBoundingBoxes;

  FacePainter(this.faceBoundingBoxes);

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = Colors.red
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    for (final rect in faceBoundingBoxes) {
      canvas.drawRect(rect, paint);
    }
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) {
    return true;
  }
}