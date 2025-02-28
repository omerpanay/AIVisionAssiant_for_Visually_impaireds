import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

class VisionService {
  static const String _baseUrl = 'https://api.openai.com/v1/chat/completions';

  Future<String> getImageDescription(String base64Image) async {
    try {
      final response = await http.post(
        Uri.parse(_baseUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${dotenv.env['OPENAI_API_KEY']}',
        },
        body: jsonEncode({
          'model': 'gpt-4-vision-preview',
          'messages': [
            {
              'role': 'user',
              'content': [
                {
                  'type': 'text',
                  'text':
                      'Bu görüntüyü detaylı bir şekilde açıkla. Önemli nesneleri, insanları ve potansiyel tehlikeleri belirt.'
                },
                {
                  'type': 'image_url',
                  'image_url': {'url': 'data:image/jpeg;base64,$base64Image'}
                }
              ]
            }
          ],
          'max_tokens': 500
        }),
      );

      print('API Yanıt Kodu: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final description = data['choices'][0]['message']['content'];
        print('API Yanıtı: $description');
        return description;
      } else {
        throw Exception(
            'API yanıt hatası: ${response.statusCode}\n${response.body}');
      }
    } catch (e) {
      print('Vision API hatası: $e');
      throw Exception('Görüntü analiz edilemedi: $e');
    }
  }
}
