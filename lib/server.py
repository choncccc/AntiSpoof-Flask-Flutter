from flask import Flask, request, jsonify
import numpy as np
import torch
import cv2
from facenet_pytorch import InceptionResnetV1, MTCNN
from sklearn.metrics.pairwise import cosine_similarity
import os

app = Flask(__name__)

#Load the VGGFace2 pre-trained model
model = InceptionResnetV1(pretrained='vggface2').eval()
mtcnn = MTCNN(keep_all=True, device='cuda' if torch.cuda.is_available() else 'cpu')

def detect_and_align_faces(img):
    img_rgb = cv2.cvtColor(img, cv2.COLOR_BGR2RGB)
    boxes, _ = mtcnn.detect(img_rgb)
    faces = []

    if boxes is not None:
        for box in boxes:
            x1, y1, x2, y2 = [int(b) for b in box]
            face = img_rgb[y1:y2, x1:x2]
            if face.size != 0:
                face = cv2.resize(face, (160, 160))
                faces.append(face)

    return faces, img_rgb, boxes

def get_face_embedding(face):
    face = face / 255.0
    face = np.transpose(face, (2, 0, 1))
    face = torch.tensor(face, dtype=torch.float32).unsqueeze(0)
    embedding = model(face).detach().cpu().numpy()
    return embedding

def texture_analysis(face):
    gray_face = cv2.cvtColor(face, cv2.COLOR_RGB2GRAY)
    laplacian_var = cv2.Laplacian(gray_face, cv2.CV_64F).var()
    return laplacian_var

def is_live(embedding, known_embedding, texture_score, threshold=0.65, texture_threshold=105.0):
    similarity = cosine_similarity(embedding, known_embedding)
    return similarity[0][0] > threshold and texture_score > texture_threshold

live_face_path = 'C:/Users/ULPI_OJT/newProj/app/assets/img.jpg'
if not os.path.isfile(live_face_path):
    print(f"Error: File '{live_face_path}' not found.")
    exit()

live_face_img = cv2.imread(live_face_path)
known_live_faces, _, _ = detect_and_align_faces(live_face_img)
if len(known_live_faces) > 0:
    known_live_face_embedding = get_face_embedding(known_live_faces[0])
else:
    print("Error: No face detected.")
    exit()

@app.route('/process_frame', methods=['POST'])
def process_frame():
    try:
        img_bytes = request.data
        np_arr = np.frombuffer(img_bytes, np.uint8)
        img = cv2.imdecode(np_arr, cv2.IMREAD_COLOR)
        faces, img_rgb, boxes = detect_and_align_faces(img)

        results = []
        if boxes is not None:
            embeddings = [get_face_embedding(face) for face in faces if face.size != 0]
            texture_scores = [texture_analysis(face) for face in faces]
            results = [is_live(embedding, known_live_face_embedding, texture_score)
                       for embedding, texture_score in zip(embeddings, texture_scores)]
        results = [bool(result) for result in results]
        
        response = {
            'results': results
        }
        return jsonify(response)
    except Exception as e:
        print(f"Error processing frame: {e}")
        return jsonify({'error': str(e)}), 500

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=True)
