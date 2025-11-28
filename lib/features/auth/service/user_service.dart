import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:flutter/material.dart'; // Para debugPrint y ScaffoldMessenger

// Asegúrate de tener tu configuración de API (ApiConfig) y la obtención del token
import 'package:sotfbee/core/config/api_config.dart'; // Ajusta la ruta si es necesario
import 'package:sotfbee/features/auth/data/datasources/auth_local_datasource.dart'; // Para obtener el token

class UserService {
  final String _baseUrl = ApiConfig.baseUrl; // Tu URL base de la API

  Future<String?> uploadProfilePicture(int userId) async {
    final ImagePicker _picker = ImagePicker();
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery); // O ImageSource.camera

    if (image == null) {
      debugPrint('❌ No se seleccionó ninguna imagen.');
      return null;
    }

    try {
      final String? token = await AuthStorage.getToken();
      if (token == null) {
        debugPrint('❌ Token de autenticación no encontrado.');
        throw Exception('Usuario no autenticado.');
      }

      var request = http.MultipartRequest(
        'PUT',
        Uri.parse('$_baseUrl/users/$userId/profile-picture'),
      );

      request.headers['Authorization'] = 'Bearer $token';

      // Añadir el archivo al request
      request.files.add(
        await http.MultipartFile.fromPath(
          'file', // El nombre de campo esperado por el backend
          image.path,
          filename: image.name,
          // contentType: MediaType('image', 'jpeg'), // Opcional, el paquete http a menudo lo deduce
        ),
      );

      debugPrint('➡️ Enviando petición PUT para foto de perfil a: ${request.url}');
      debugPrint('➡️ Con encabezados: ${request.headers}');
      debugPrint('➡️ Con archivo: ${image.name}');

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      debugPrint('⬅️ Respuesta recibida para foto de perfil. Status: ${response.statusCode}');
      debugPrint('Response Body: ${response.body}');

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);
        final String newProfilePictureUrl = data['profile_picture'];
        debugPrint('✅ Foto de perfil actualizada con éxito: $newProfilePictureUrl');
        return newProfilePictureUrl;
      } else {
        debugPrint('❌ Error al actualizar foto de perfil: ${response.body}');
        throw Exception('Error al actualizar foto de perfil: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('❌ Excepción al subir foto de perfil: $e');
      return null;
    }
  }

  void onUpdateProfilePicturePressed(BuildContext context, int userId) async {
    String? newUrl = await uploadProfilePicture(userId);
    if (newUrl != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Foto de perfil actualizada.')),
      );
      // Aquí podrías querer actualizar el estado de tu UI
      // Por ejemplo, usando Provider.of<UserProfileProvider>(context, listen: false).updatePicture(newUrl);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fallo al actualizar la foto de perfil.')),
      );
    }
  }
}
