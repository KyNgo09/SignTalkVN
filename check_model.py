import tensorflow as tf

model_path = r"D:\CTU\SignTalkVN\signtalk_app\assets\models\signtalk_model.tflite"
try:
    interpreter = tf.lite.Interpreter(model_path=model_path)
    interpreter.allocate_tensors()
    print("SUCCESS")
    for detail in interpreter.get_tensor_details():
        print(detail['name'], detail['shape'], detail['dtype'])
except Exception as e:
    print("FAILED:", e)
    
# check if it uses flex ops
try:
    with open(model_path, 'rb') as f:
        model_content = f.read()
    print("Flex op present:", b"Flex" in model_content)
    print("SelectTfOps present:", b"SelectTfOps" in model_content)
except:
    pass
