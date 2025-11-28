import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:sotfbee/core/config/api_config.dart';
import 'package:sotfbee/features/auth/data/datasources/auth_local_datasource.dart';
import '../models/enhanced_models.dart';
import 'local_db_service.dart';
import 'package:flutter/foundation.dart';

class EnhancedApiService {
  static final String _baseUrl = ApiConfig.baseUrl;
  static final Duration _timeout = ApiConfig.timeout;

  static Future<Map<String, String>> get _headers async {
    final token = await AuthStorage.getToken();
    if (token == null || token.isEmpty) {
      throw Exception(
        'No se encontró el token de autenticación. Por favor, inicia sesión de nuevo.',
      );
    }
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  // ==================== AUTH ====================

  static Future<Usuario?> obtenerPerfil() async {
    try {
      final response = await http
          .get(Uri.parse('$_baseUrl/users/me'), headers: await _headers)
          .timeout(_timeout);

      if (response.statusCode == 200) {
        final dynamic decodedBody = json.decode(response.body);
        if (decodedBody is Map<String, dynamic>) {
          final user = Usuario.fromJson(decodedBody);
          print(
            'Perfil de usuario obtenido: ID=${user.id}, Email=${user.email}',
          );
          return user;
        } else {
          throw Exception(
            'Formato de respuesta inesperado para perfil de usuario',
          );
        }
      } else if (response.statusCode == 401) {
        AuthStorage.deleteToken();
        return null;
      } else {
        throw Exception('Error al obtener perfil: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error de conexión: $e');
    }
  }

  static Future<String> login(String email, String password) async {
    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl/login'),
            headers: await _headers,
            body: json.encode({'email': email, 'password': password}),
          )
          .timeout(_timeout);

      if (response.statusCode == 200) {
        final result = json.decode(response.body);
        final token = result['token'] ?? result['access_token'];
        if (token != null) {
          await AuthStorage.saveToken(token);
          return token;
        } else {
          throw Exception('Token no recibido');
        }
      } else {
        throw Exception('Credenciales inválidas');
      }
    } catch (e) {
      throw Exception('Error de conexión: $e');
    }
  }

  // ==================== APIARIOS ====================
  static Future<List<Apiario>> obtenerApiarios({int? userId}) async {
    try {
      int? effectiveUserId = userId;
      if (effectiveUserId == null) {
        final user = await obtenerPerfil();
        if (user == null) {
          print('Usuario no autenticado, no se pueden obtener apiarios.');
          return [];
        }
        effectiveUserId = user.id;
      }

      final String url = '$_baseUrl/users/$effectiveUserId/apiaries';
      print('Obteniendo apiarios para userId: $effectiveUserId desde: $url');

      final response = await http
          .get(Uri.parse(url), headers: await _headers)
          .timeout(_timeout);

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        final apiarios = data.map((json) => Apiario.fromJson(json)).toList();

        // Guardar en la base de datos local
        final dbService = LocalDBService();
        for (final apiario in apiarios) {
          await dbService.insertApiario(apiario);
        }

        return apiarios;
      } else if (response.statusCode == 404) {
        return [];
      } else if (response.statusCode == 401) {
        AuthStorage.deleteToken();
        throw Exception('Sesión expirada');
      } else {
        throw Exception('Error al obtener apiarios: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error de conexión: $e');
    }
  }

  static Future<int> crearApiario(Map<String, dynamic> data) async {
    try {
      final user = await obtenerPerfil();
      if (user == null) throw Exception('Usuario no autenticado');

      if (data['name'] == null && data['nombre'] == null) {
        throw Exception('Nombre es requerido');
      }

      final response = await http
          .post(
            Uri.parse('$_baseUrl/apiaries'),
            headers: await _headers,
            body: json.encode({
              'name': data['name'] ?? data['nombre'],
              'user_id': user.id,
              'location': data['location'] ?? data['ubicacion'],
            }),
          )
          .timeout(_timeout);

      if (response.statusCode == 201) {
        return json.decode(response.body)['id'];
      } else {
        throw Exception('Error: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      throw Exception('Error al crear apiario: $e');
    }
  }

  static Future<Apiario?> obtenerApiario(int id) async {
    try {
      final response = await http
          .get(Uri.parse('$_baseUrl/apiaries/$id'), headers: await _headers)
          .timeout(_timeout);

      if (response.statusCode == 200) {
        return Apiario.fromJson(json.decode(response.body));
      } else if (response.statusCode == 404) {
        return null;
      } else {
        throw Exception('Error al obtener apiario: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error de conexión: $e');
    }
  }

  static Future<void> actualizarApiario(
    int id,
    Map<String, dynamic> data,
  ) async {
    try {
      final response = await http
          .put(
            Uri.parse('$_baseUrl/apiaries/$id'),
            headers: await _headers,
            body: json.encode(data),
          )
          .timeout(_timeout);

      if (response.statusCode != 200) {
        throw Exception('Error al actualizar apiario: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error de conexión: $e');
    }
  }

  static Future<void> eliminarApiario(int id) async {
    try {
      final response = await http
          .delete(Uri.parse('$_baseUrl/apiaries/$id'), headers: await _headers)
          .timeout(_timeout);

      if (response.statusCode != 200) {
        throw Exception('Error al eliminar apiario: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error de conexión: $e');
    }
  }

  // ========== Métodos para Colmenas ==========
  static Future<List<Colmena>> obtenerColmenas(int apiarioId) async {
    try {
      final response = await http
          .get(
            Uri.parse('$_baseUrl/apiaries/$apiarioId/hives'),
            headers: await _headers,
          )
          .timeout(_timeout);

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        final colmenas = data.map((json) => Colmena.fromJson(json)).toList();

        // Guardar en la base de datos local
        final dbService = LocalDBService();
        for (final colmena in colmenas) {
          await dbService.insertColmena(colmena);
        }

        return colmenas;
      }
      throw Exception('Error al obtener colmenas: ${response.statusCode}');
    } catch (e) {
      throw Exception('Error de conexión: $e');
    }
  }

  static Future<int> crearColmena(
    int apiarioId,
    Map<String, dynamic> data,
  ) async {
    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl/apiaries/$apiarioId/hives'),
            headers: await _headers,
            body: json.encode(data),
          )
          .timeout(_timeout);

      if (response.statusCode == 201) {
        return json.decode(response.body)['id'];
      }
      throw Exception(
        'Error al crear colmena: ${response.statusCode} - ${response.body}',
      );
    } catch (e) {
      throw Exception('Error de conexión: $e');
    }
  }

  static Future<void> actualizarColmena(
    int colmenaId,
    Map<String, dynamic> data,
  ) async {
    try {
      final response = await http
          .put(
            Uri.parse('$_baseUrl/hives/$colmenaId'),
            headers: await _headers,
            body: json.encode(data),
          )
          .timeout(_timeout);

      if (response.statusCode != 200) {
        throw Exception('Error al actualizar: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error de conexión: $e');
    }
  }

  static Future<void> eliminarColmena(int colmenaId) async {
    try {
      final response = await http
          .delete(
            Uri.parse('$_baseUrl/hives/$colmenaId'),
            headers: await _headers,
          )
          .timeout(_timeout);

      if (response.statusCode != 200) {
        throw Exception('Error al eliminar: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error de conexión: $e');
    }
  }

  // ==================== PREGUNTAS ====================
  static Future<List<Pregunta>> obtenerPreguntasApiario(
    int apiarioId, {
    bool soloActivas = true,
  }) async {
    final dbService = LocalDBService();
    try {
      String url = '$_baseUrl/apiaries/$apiarioId/questions';
      if (soloActivas) {
        url += '?active_only=true';
      }

      final response = await http
          .get(Uri.parse(url), headers: await _headers)
          .timeout(_timeout);

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        final preguntas = data.map((json) => Pregunta.fromJson(json)).toList();

        // Guardar en la base de datos local
        for (final pregunta in preguntas) {
          await dbService.savePregunta(pregunta);
        }

        return preguntas;
      } else {
        throw Exception(
          'Error al obtener preguntas del servidor: ${response.statusCode} - ${response.body}',
        );
      }
    } catch (e) {
      // Si falla la obtención del servidor, intentar desde la base de datos local
      debugPrint(
        "⚠️ Error al obtener preguntas del servidor, intentando desde local: $e",
      );
      return await dbService.getPreguntasByApiario(apiarioId);
    }
  }

  static Future<int> crearPregunta(Pregunta pregunta) async {
    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl/questions'),
            headers: await _headers,
            body: json.encode(pregunta.toJson()),
          )
          .timeout(_timeout);

      if (response.statusCode == 201) {
        final result = json.decode(response.body);
        return result['id'];
      } else {
        final errorBody = json.decode(response.body);
        throw Exception(
          'Error al crear pregunta: ${response.statusCode} - ${errorBody['error'] ?? 'Error desconocido'}',
        );
      }
    } catch (e) {
      throw Exception('Error de conexión: $e');
    }
  }

  static Future<int> crearPreguntaDesdeTemplate(
    Map<String, dynamic> data,
  ) async {
    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl/questions'),
            headers: await _headers,
            body: json.encode(data),
          )
          .timeout(_timeout);

      if (response.statusCode == 201) {
        return json.decode(response.body)['id'];
      } else {
        final error = json.decode(response.body);
        throw Exception('Error: ${error['error'] ?? 'desconocido'}');
      }
    } catch (e) {
      throw Exception('Error de red al crear pregunta: $e');
    }
  }

  static Future<void> actualizarPregunta(
    int preguntaId,
    Map<String, dynamic> data,
  ) async {
    try {
      final response = await http
          .put(
            Uri.parse('$_baseUrl/questions/$preguntaId'),
            headers: await _headers,
            body: json.encode(data),
          )
          .timeout(_timeout);

      if (response.statusCode != 200) {
        throw Exception('Error al actualizar pregunta: ${response.statusCode}');
      }

      // Actualizar también en la base de datos local
      final dbService = LocalDBService();
      final pregunta = Pregunta.fromJson(
        data..['id'] = preguntaId,
      ); // Reconstruir Pregunta con ID
      await dbService.savePregunta(pregunta);
    } catch (e) {
      // Si falla la actualización en el servidor, al menos guardar localmente
      final dbService = LocalDBService();
      final pregunta = Pregunta.fromJson(
        data..['id'] = preguntaId,
      ); // Reconstruir Pregunta con ID
      await dbService.savePregunta(pregunta);
      throw Exception('Error de conexión al actualizar pregunta: $e');
    }
  }

  static Future<void> eliminarPregunta(int preguntaId) async {
    try {
      final response = await http
          .delete(
            Uri.parse('$_baseUrl/questions/$preguntaId'),
            headers: await _headers,
          )
          .timeout(_timeout);

      if (response.statusCode != 200) {
        throw Exception('Error al eliminar pregunta: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error de conexión: $e');
    }
  }

  static Future<void> reordenarPreguntas(
    int apiarioId,
    List<String> orden,
  ) async {
    try {
      final response = await http
          .put(
            Uri.parse('$_baseUrl/apiaries/$apiarioId/questions/reorder'),
            headers: await _headers,
            body: json.encode({'order': orden}),
          )
          .timeout(_timeout);

      if (response.statusCode != 200) {
        throw Exception('Error al reordenar preguntas: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error de conexión: $e');
    }
  }

  static Future<Map<String, dynamic>> loadDefaultQuestions(int apiaryId) async {
    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl/questions/load_defaults/$apiaryId'),
            headers: await _headers,
          )
          .timeout(_timeout);

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw Exception(
          'Error al cargar preguntas por defecto: ${response.statusCode}',
        );
      }
    } catch (e) {
      throw Exception('Error de conexión al cargar preguntas por defecto: $e');
    }
  }

  // ==================== NOTIFICACIONES REINA ====================
  static Future<List<NotificacionReina>> obtenerNotificacionesReina({
    int? apiarioId,
    bool soloNoLeidas = false,
    int limit = 50,
    int offset = 0,
  }) async {
    try {
      String url = '$_baseUrl/queen-notifications';
      List<String> params = [];

      if (apiarioId != null) params.add('apiario_id=$apiarioId');
      if (soloNoLeidas) params.add('unread_only=true');
      params.add('limit=$limit');
      params.add('offset=$offset');

      if (params.isNotEmpty) {
        url += '?${params.join('&')}';
      }

      final response = await http
          .get(Uri.parse(url), headers: await _headers)
          .timeout(_timeout);

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.map((json) => NotificacionReina.fromJson(json)).toList();
      } else {
        return [];
      }
    } catch (e) {
      return [];
    }
  }

  static Future<int> crearNotificacionReina(
    NotificacionReina notificacion,
  ) async {
    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl/queen-notifications'),
            headers: await _headers,
            body: json.encode(notificacion.toJson()),
          )
          .timeout(_timeout);

      if (response.statusCode == 201) {
        final result = json.decode(response.body);
        return result['id'] ?? -1;
      } else {
        throw Exception('Error al crear notificación: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error de conexión: $e');
    }
  }

  static Future<void> marcarNotificacionComoLeida(int notificacionId) async {
    try {
      final response = await http
          .put(
            Uri.parse('$_baseUrl/queen-notifications/$notificacionId/read'),
            headers: await _headers,
          )
          .timeout(_timeout);

      if (response.statusCode != 200) {
        throw Exception('Error al marcar notificación: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error de conexión: $e');
    }
  }

  static Future<int> createMonitoreo({
    required int idColmena,
    required int idApiario,
    required String fecha,
    required List<Map<String, dynamic>> respuestas,
    Map<String, dynamic>? datosAdicionales,
  }) async {
    try {
      final body = {
        'id_colmena': idColmena,
        'id_apiario': idApiario,
        'fecha': fecha,
        'respuestas': respuestas,
        'datos_adicionales': datosAdicionales,
      };

      debugPrint('➡️ Enviando POST a: $_baseUrl/monitoreos');
      debugPrint('Payload: ${json.encode(body)}');
      debugPrint('Headers: ${await _headers}');

      final response = await http
          .post(
            Uri.parse('$_baseUrl/monitoreos'),
            headers: await _headers,
            body: json.encode(body),
          )
          .timeout(_timeout);

      debugPrint('⬅️ Respuesta recibida para POST /monitoreos. Status: ${response.statusCode}');
      debugPrint('Response Body: ${response.body}');

      if (response.statusCode == 201) {
        final result = json.decode(response.body);
        debugPrint('✅ Backend respondió 201 para monitoreo. Body: $result');
        return result['id'];
      } else {
        throw Exception(
          'Error al crear monitoreo: ${response.statusCode} - ${response.body}',
        );
      }
    } catch (e) {
      throw Exception('Error de conexión al crear monitoreo: $e');
    }
  }

  // ==================== UTILIDADES ====================
  static Future<bool> verificarConexion() async {
    try {
      final response = await http
          .get(Uri.parse('$_baseUrl/health'), headers: await _headers)
          .timeout(Duration(seconds: 10));
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  static Future<bool> hasInternetConnection() async {
    try {
      final result = await InternetAddress.lookup(
        'google.com',
      ).timeout(Duration(seconds: 5));
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  static Future<Map<String, dynamic>> obtenerEstadisticas({
    int? apiarioId,
  }) async {
    try {
      String url = '$_baseUrl/stats';
      if (apiarioId != null) {
        url += '?apiario_id=$apiarioId';
      }

      final response = await http
          .get(Uri.parse(url), headers: await _headers)
          .timeout(_timeout);

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        return {
          'total_apiarios': 0,
          'total_colmenas': 0,
          'total_monitoreos': 0,
          'monitoreos_pendientes': 0,
        };
      }
    } catch (e) {
      return {
        'total_apiarios': 0,
        'total_colmenas': 0,
        'total_monitoreos': 0,
        'monitoreos_pendientes': 0,
      };
    }
  }

  // ==================== BANCO DE PREGUNTAS ====================
  static Future<List<PreguntaTemplate>> obtenerPlantillasPreguntas() async {
    try {
      final response = await http
          .get(Uri.parse('$_baseUrl/questions/bank'), headers: await _headers)
          .timeout(_timeout);

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.map((json) => PreguntaTemplate.fromJson(json)).toList();
      } else {
        throw Exception(
          'Error al obtener banco de preguntas: ${response.statusCode}',
        );
      }
    } catch (e) {
      print('Error de red, usando banco de preguntas local: $e');
      return _fallbackQuestionBank();
    }
  }

  static List<PreguntaTemplate> _fallbackQuestionBank() {
    final String localData = '''
    {
      "preguntas": [
        {
          "id": "estado_general",
          "categoria": "Estado de la Colmena",
          "pregunta": "¿Cuál es el estado general de la colmena?",
          "tipo": "opciones",
          "obligatoria": true,
          "opciones": ["Excelente", "Bueno", "Regular", "Malo"]
        },
        {
          "id": "poblacion",
          "categoria": "Estado de la Colmena",
          "pregunta": "Nivel de población",
          "tipo": "opciones",
          "obligatoria": true,
          "opciones": ["Alta", "Media", "Baja"]
        },
        {
          "id": "comportamiento",
          "categoria": "Estado de la Colmena",
          "pregunta": "Comportamiento de las abejas",
          "tipo": "opciones",
          "obligatoria": true,
          "opciones": ["Dócil", "Nervioso", "Agresivo"]
        },
        {
          "id": "cantidad_cria",
          "categoria": "Producción",
          "pregunta": "Cantidad de cuadros de cría",
          "tipo": "numero",
          "obligatoria": true,
          "min": 0,
          "max": 20
        },
        {
          "id": "cantidad_miel",
          "categoria": "Producción",
          "pregunta": "Cantidad de cuadros de miel",
          "tipo": "numero",
          "obligatoria": true,
          "min": 0,
          "max": 20
        },
        {
          "id": "presencia_reina",
          "categoria": "Salud",
          "pregunta": "¿Se observó a la reina?",
          "tipo": "opciones",
          "obligatoria": true,
          "opciones": ["Sí", "No"]
        },
        {
          "id": "celdas_reales",
          "categoria": "Salud",
          "pregunta": "¿Presencia de celdas reales?",
          "tipo": "opciones",
          "obligatoria": true,
          "opciones": ["Sí", "No"]
        },
        {
          "id": "enfermedades",
          "categoria": "Salud",
          "pregunta": "¿Signos de enfermedades (Loque, Varroa, etc.)?",
          "tipo": "texto",
          "obligatoria": false
        },
        {
          "id": "necesita_alimentacion",
          "categoria": "Alimentación",
          "pregunta": "¿Necesita alimentación suplementaria?",
          "tipo": "opciones",
          "obligatoria": true,
          "opciones": ["Sí", "No"]
        },
        {
          "id": "espacio_disponible",
          "categoria": "Mantenimiento",
          "pregunta": "¿Necesita más espacio (alzas)?",
          "tipo": "opciones",
          "obligatoria": true,
          "opciones": ["Sí", "No"]
        }
      ]
    }
    ''';
    final data = json.decode(localData);
    final List<dynamic> preguntasJson = data['preguntas'];
    return preguntasJson
        .map((json) => PreguntaTemplate.fromJson(json))
        .toList();
  }
}
