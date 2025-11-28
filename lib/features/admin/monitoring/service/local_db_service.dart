import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:sotfbee/features/admin/monitoring/models/enhanced_models.dart'
    as enhanced_models;
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:hive/hive.dart';

class LocalDBService {
  static Database? _database;
  static Box? _hiveBox;

  static const String _databaseName = 'beehive_monitoring.db';
  static const int _databaseVersion =
      4; // Incrementado para agregar tablas de monitoreo
  static const String _hiveBoxName = 'beehive_data';

  Future<Database?> get database async {
    if (kIsWeb) return null; // En web usamos Hive

    if (_database != null && _database!.isOpen) return _database;

    // Configuración para desktop (no web)
    if (defaultTargetPlatform != TargetPlatform.android &&
        defaultTargetPlatform != TargetPlatform.iOS) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    _database = await _initDatabase();
    return _database;
  }

  Future<Box> get hiveBox async {
    if (!kIsWeb) throw UnsupportedError('Hive solo se usa en Web');

    _hiveBox ??= await Hive.openBox(_hiveBoxName);
    return _hiveBox!;
  }

  Future<Database> _initDatabase() async {
    try {
      String path = join(await getDatabasesPath(), _databaseName);
      debugPrint('📁 Ruta de la base de datos: $path');

      return await openDatabase(
        path,
        version: _databaseVersion,
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
      );
    } catch (e) {
      debugPrint('❌ Error al inicializar la base de datos: $e');
      rethrow;
    }
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('PRAGMA foreign_keys = ON');

    // Tabla apiarios
    await db.execute('''
      CREATE TABLE apiarios (
        id INTEGER PRIMARY KEY,
        nombre TEXT NOT NULL,
        ubicacion TEXT NOT NULL,
        user_id INTEGER,
        fecha_creacion TEXT,
        fecha_actualizacion TEXT,
        metadatos TEXT,
        sincronizado INTEGER DEFAULT 0
      )
    ''');

    // Tabla colmenas
    await db.execute('''
      CREATE TABLE colmenas (
        id INTEGER PRIMARY KEY,
        numero_colmena INTEGER NOT NULL,
        id_apiario INTEGER NOT NULL,
        activa INTEGER DEFAULT 1,
        fecha_creacion TEXT,
        fecha_ultima_inspeccion TEXT,
        estado_reina TEXT,
        metadatos TEXT,
        sincronizado INTEGER DEFAULT 0,
        FOREIGN KEY (id_apiario) REFERENCES apiarios (id) ON DELETE CASCADE
      )
    ''');

    // Tabla preguntas
    await db.execute('''
      CREATE TABLE preguntas (
        id TEXT PRIMARY KEY,
        texto TEXT NOT NULL,
        tipo_respuesta TEXT,
        seleccionada INTEGER DEFAULT 0,
        orden INTEGER NOT NULL,
        activa INTEGER DEFAULT 1,
        obligatoria INTEGER DEFAULT 0,
        apiario_id INTEGER,
        fecha_creacion TEXT,
        FOREIGN KEY (apiario_id) REFERENCES apiarios (id) ON DELETE CASCADE
      )
    ''');

    // Tabla opciones (para preguntas de opción múltiple)
    await db.execute('''
      CREATE TABLE opciones (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        pregunta_id TEXT NOT NULL,
        valor TEXT NOT NULL,
        descripcion TEXT,
        FOREIGN KEY (pregunta_id) REFERENCES preguntas (id) ON DELETE CASCADE
      )
    ''');

    // Tabla notificaciones_reina
    await db.execute('''
      CREATE TABLE notificaciones_reina (
        id INTEGER PRIMARY KEY,
        apiario_id INTEGER NOT NULL,
        colmena_id INTEGER,
        tipo TEXT NOT NULL,
        titulo TEXT NOT NULL,
        mensaje TEXT NOT NULL,
        prioridad TEXT NOT NULL,
        leida INTEGER DEFAULT 0,
        fecha_creacion TEXT NOT NULL,
        fecha_vencimiento TEXT,
        metadatos TEXT,
        sincronizado INTEGER DEFAULT 0,
        FOREIGN KEY (apiario_id) REFERENCES apiarios (id) ON DELETE CASCADE,
        FOREIGN KEY (colmena_id) REFERENCES colmenas (id) ON DELETE SET NULL
      )
    ''');

    // Tabla monitoreos (nueva)
    await db.execute('''
      CREATE TABLE monitoreos (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        colmena_id INTEGER NOT NULL,
        apiario_id INTEGER NOT NULL,
        fecha TEXT NOT NULL,
        sincronizado INTEGER DEFAULT 0,
        FOREIGN KEY (colmena_id) REFERENCES colmenas (id) ON DELETE CASCADE,
        FOREIGN KEY (apiario_id) REFERENCES apiarios (id) ON DELETE CASCADE
      )
    ''');

    // Tabla respuestas_monitoreo (nueva)
    await db.execute('''
      CREATE TABLE respuestas_monitoreo (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        monitoreo_id INTEGER NOT NULL,
        pregunta_id TEXT NOT NULL,
        pregunta_texto TEXT NOT NULL,
        respuesta TEXT NOT NULL,
        tipo_respuesta TEXT NOT NULL,
        fecha_respuesta TEXT NOT NULL,
        FOREIGN KEY (monitoreo_id) REFERENCES monitoreos (id) ON DELETE CASCADE
      )
    ''');

    debugPrint('✅ Tablas creadas correctamente');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('''
        ALTER TABLE apiarios ADD COLUMN sincronizado INTEGER DEFAULT 0
      ''');
      await db.execute('''
        ALTER TABLE colmenas ADD COLUMN sincronizado INTEGER DEFAULT 0
      ''');
    }
    if (oldVersion < 3) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS notificaciones_reina (
          id INTEGER PRIMARY KEY,
          apiario_id INTEGER NOT NULL,
          colmena_id INTEGER,
          tipo TEXT NOT NULL,
          titulo TEXT NOT NULL,
          mensaje TEXT NOT NULL,
          prioridad TEXT NOT NULL,
          leida INTEGER DEFAULT 0,
          fecha_creacion TEXT NOT NULL,
          fecha_vencimiento TEXT,
          metadatos TEXT,
          sincronizado INTEGER DEFAULT 0,
          FOREIGN KEY (apiario_id) REFERENCES apiarios (id) ON DELETE CASCADE,
          FOREIGN KEY (colmena_id) REFERENCES colmenas (id) ON DELETE SET NULL
        )
      ''');
    }
    if (oldVersion < 4) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS monitoreos (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          colmena_id INTEGER NOT NULL,
          apiario_id INTEGER NOT NULL,
          fecha TEXT NOT NULL,
          sincronizado INTEGER DEFAULT 0,
          FOREIGN KEY (colmena_id) REFERENCES colmenas (id) ON DELETE CASCADE,
          FOREIGN KEY (apiario_id) REFERENCES apiarios (id) ON DELETE CASCADE
        )
      ''');

      await db.execute('''
        CREATE TABLE IF NOT EXISTS respuestas_monitoreo (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          monitoreo_id INTEGER NOT NULL,
          pregunta_id TEXT NOT NULL,
          pregunta_texto TEXT NOT NULL,
          respuesta TEXT NOT NULL,
          tipo_respuesta TEXT NOT NULL,
          fecha_respuesta TEXT NOT NULL,
          FOREIGN KEY (monitoreo_id) REFERENCES monitoreos (id) ON DELETE CASCADE
        )
      ''');
    }
  }

  // ================ APIARIOS ================
  Future<int> insertApiario(enhanced_models.Apiario apiario) async {
    if (kIsWeb) {
      final box = await hiveBox;
      await box.put('apiario_${apiario.id}', apiario.toJson());
      return apiario.id ?? 0;
    } else {
      final db = await database;
      return await db!.insert('apiarios', {
        ...apiario.toJson(),
        'fecha_creacion': DateTime.now().toIso8601String(),
        'sincronizado': 0,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  Future<List<enhanced_models.Apiario>> getApiarios() async {
    if (kIsWeb) {
      final box = await hiveBox;
      final data = box.toMap();
      return data.entries
          .where((e) => e.key.toString().startsWith('apiario_'))
          .map(
            (e) => enhanced_models.Apiario.fromJson(
              Map<String, dynamic>.from(e.value),
            ),
          )
          .toList();
    } else {
      final db = await database;
      final List<Map<String, dynamic>> maps = await db!.query(
        'apiarios',
        orderBy: 'nombre ASC',
      );
      return List.generate(maps.length, (i) {
        return enhanced_models.Apiario.fromJson(maps[i]);
      });
    }
  }

  Future<int> updateApiario(enhanced_models.Apiario apiario) async {
    if (kIsWeb) {
      final box = await hiveBox;
      await box.put('apiario_${apiario.id}', apiario.toJson());
      return apiario.id ?? 0;
    } else {
      final db = await database;
      return await db!.update(
        'apiarios',
        {
          ...apiario.toJson(),
          'fecha_actualizacion': DateTime.now().toIso8601String(),
          'sincronizado': 0,
        },
        where: 'id = ?',
        whereArgs: [apiario.id],
      );
    }
  }

  Future<int> deleteApiario(int? id) async {
    if (kIsWeb) {
      final box = await hiveBox;
      await box.delete('apiario_$id');
      return 1;
    } else {
      final db = await database;
      return await db!.delete('apiarios', where: 'id = ?', whereArgs: [id]);
    }
  }

  // ================ COLMENAS ================
  Future<int> insertColmena(enhanced_models.Colmena colmena) async {
    if (kIsWeb) {
      final box = await hiveBox;
      await box.put('colmena_${colmena.id}', colmena.toJson());
      return colmena.id ?? 0;
    } else {
      final db = await database;
      return await db!.insert('colmenas', {
        ...colmena.toJson(),
        'fecha_creacion': DateTime.now().toIso8601String(),
        'sincronizado': 0,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  Future<List<enhanced_models.Colmena>> getColmenasByApiario(
    int apiarioId,
  ) async {
    if (kIsWeb) {
      final box = await hiveBox;
      final data = box.toMap();
      return data.entries
          .where((e) => e.key.toString().startsWith('colmena_'))
          .map(
            (e) => enhanced_models.Colmena.fromJson(
              Map<String, dynamic>.from(e.value),
            ),
          )
          .where((c) => c.idApiario == apiarioId && c.activa == true)
          .toList();
    } else {
      final db = await database;
      final List<Map<String, dynamic>> maps = await db!.query(
        'colmenas',
        where: 'id_apiario = ? AND activa = 1',
        whereArgs: [apiarioId],
        orderBy: 'numero_colmena ASC',
      );
      return List.generate(maps.length, (i) {
        return enhanced_models.Colmena.fromJson(maps[i]);
      });
    }
  }

  // ================ PREGUNTAS ================
  Future<List<enhanced_models.Pregunta>> getPreguntasByApiario(
    int apiarioId,
  ) async {
    if (kIsWeb) {
      final box = await hiveBox;
      final data = box.toMap();
      return data.entries
          .where((e) => e.key.toString().startsWith('pregunta_'))
          .map(
            (e) => enhanced_models.Pregunta.fromJson(
              Map<String, dynamic>.from(e.value),
            ),
          )
          .where((p) => p.apiarioId == apiarioId)
          .toList();
    } else {
      final db = await database;
      final List<Map<String, dynamic>> maps = await db!.query(
        'preguntas',
        where: 'apiario_id = ?',
        whereArgs: [apiarioId],
        orderBy: 'orden ASC',
      );

      // Obtener opciones para cada pregunta
      final preguntas = List.generate(maps.length, (i) {
        return enhanced_models.Pregunta.fromJson(maps[i]);
      });

      for (var pregunta in preguntas) {
        final opciones = await db.query(
          'opciones',
          where: 'pregunta_id = ?',
          whereArgs: [pregunta.id],
        );
        if (opciones.isNotEmpty) {
          pregunta.opciones = opciones
              .map((o) => enhanced_models.Opcion.fromJson(o))
              .toList();
        }
      }

      return preguntas;
    }
  }

  Future<int> savePregunta(enhanced_models.Pregunta pregunta) async {
    if (kIsWeb) {
      final box = await hiveBox;
      await box.put('pregunta_${pregunta.id}', pregunta.toJson());
      return 1;
    } else {
      final db = await database;
      await db!.insert('preguntas', {
        'id': pregunta.id,
        'texto': pregunta.texto,
        'tipo_respuesta': pregunta.tipoRespuesta,
        'seleccionada': pregunta.seleccionada ? 1 : 0, // Guardar como entero
        'orden': pregunta.orden,
        'activa': pregunta.activa ? 1 : 0,
        'obligatoria': pregunta.obligatoria ? 1 : 0,
        'apiario_id': pregunta.apiarioId,
        'fecha_creacion': pregunta.fechaCreacion?.toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);

      // Guardar opciones si existen
      if (pregunta.opciones != null && pregunta.opciones!.isNotEmpty) {
        // Eliminar opciones antiguas primero
        await db.delete(
          'opciones',
          where: 'pregunta_id = ?',
          whereArgs: [pregunta.id],
        );

        // Insertar nuevas opciones
        for (var opcion in pregunta.opciones!) {
          await db.insert('opciones', {
            'pregunta_id': pregunta.id,
            'valor': opcion.valor,
            'descripcion': opcion.descripcion,
          });
        }
      }
      return 1;
    }
  }

  Future<int> deletePregunta(String id) async {
    if (kIsWeb) {
      final box = await hiveBox;
      await box.delete('pregunta_$id');
      return 1;
    } else {
      final db = await database;
      // Eliminar opciones primero por la relación foreign key
      await db!.delete('opciones', where: 'pregunta_id = ?', whereArgs: [id]);

      // Luego eliminar la pregunta
      return await db.delete('preguntas', where: 'id = ?', whereArgs: [id]);
    }
  }

  // ================ NOTIFICACIONES REINA ================
  Future<List<enhanced_models.NotificacionReina>>
  getNotificacionesReina() async {
    if (kIsWeb) {
      final box = await hiveBox;
      final data = box.toMap();
      return data.entries
          .where((e) => e.key.toString().startsWith('notificacion_'))
          .map(
            (e) => enhanced_models.NotificacionReina.fromJson(
              Map<String, dynamic>.from(e.value),
            ),
          )
          .toList();
    } else {
      final db = await database;
      final List<Map<String, dynamic>> maps = await db!.query(
        'notificaciones_reina',
        orderBy: 'fecha_creacion DESC',
      );
      return List.generate(maps.length, (i) {
        return enhanced_models.NotificacionReina.fromJson(maps[i]);
      });
    }
  }

  Future<int> saveNotificacionReina(
    enhanced_models.NotificacionReina notificacion,
  ) async {
    if (kIsWeb) {
      final box = await hiveBox;
      await box.put('notificacion_${notificacion.id}', notificacion.toJson());
      return notificacion.id ?? 0;
    } else {
      final db = await database;
      return await db!.insert(
        'notificaciones_reina',
        notificacion.toJson(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }

  Future<int> deleteNotificacionReina(int id) async {
    if (kIsWeb) {
      final box = await hiveBox;
      await box.delete('notificacion_$id');
      return 1;
    } else {
      final db = await database;
      return await db!.delete(
        'notificaciones_reina',
        where: 'id = ?',
        whereArgs: [id],
      );
    }
  }

  // ================ MONITOREOS ================
  Future<int> saveMonitoreo(Map<String, dynamic> data) async {
    if (kIsWeb) {
      final box = await hiveBox;
      final id = DateTime.now().millisecondsSinceEpoch;
      data['id'] = id; // Add the generated ID to the data map
      await box.put('monitoreo_$id', data);
      return id;
    } else {
      final db = await database;
      debugPrint('💾 Intentando insertar monitoreo localmente: $data');
      final insertedId = await db!.insert('monitoreos', {
        'colmena_id': data['colmena_id'],
        'apiario_id': data['id_apiario'],
        'fecha': data['fecha'],
        'sincronizado': 0,
      });
      debugPrint('✅ Monitoreo local insertado con ID: $insertedId');
      return insertedId;
    }
  }

  Future<int> saveRespuestas(
    int monitoreoId,
    List<enhanced_models.MonitoreoRespuesta> respuestas,
  ) async {
    if (kIsWeb) {
      final box = await hiveBox;
      await box.put(
        'respuestas_$monitoreoId',
        respuestas.map((r) => r.toJson()).toList(),
      );
      return respuestas.length;
    } else {
      final db = await database;
      int count = 0;
      for (var respuesta in respuestas) {
        await db!.insert('respuestas_monitoreo', {
          'monitoreo_id': monitoreoId,
          'pregunta_id': respuesta.preguntaId,
          'pregunta_texto': respuesta.preguntaTexto,
          'respuesta': respuesta.respuesta.toString(),
          'tipo_respuesta': respuesta.tipoRespuesta ?? 'texto',
          'fecha_respuesta':
              respuesta.fechaRespuesta?.toIso8601String() ??
              DateTime.now().toIso8601String(),
        });
        count++;
      }
      return count;
    }
  }

  Future<List<Map<String, dynamic>>> getMonitoreosPendientes() async {
    if (kIsWeb) {
      final box = await hiveBox;
      final data = box.toMap();
      final pendientesWeb = data.entries
          .where((e) => e.key.toString().startsWith('monitoreo_'))
          .map((e) => Map<String, dynamic>.from(e.value))
          .toList();
      debugPrint('🔍 Encontrados ${pendientesWeb.length} monitoreos pendientes (web).');
      return pendientesWeb;
    } else {
      final db = await database;
      final monitoreos = await db!.query(
        'monitoreos',
        where: 'sincronizado = 0',
      );
      debugPrint('🔍 Encontrados ${monitoreos.length} monitoreos pendientes (SQLite).');

      List<Map<String, dynamic>> result = [];
      for (var monitoreo in monitoreos) {
        final respuestas = await db.query(
          'respuestas_monitoreo',
          where: 'monitoreo_id = ?',
          whereArgs: [monitoreo['id']],
        );

        result.add({
          'id': monitoreo['id'],
          'colmena_id': monitoreo['colmena_id'],
          'apiario_id': monitoreo['apiario_id'],
          'fecha': monitoreo['fecha'],
          'respuestas': respuestas,
        });
      }
      return result;
    }
  }

  Future<int> markMonitoreoSincronizado(int id) async {
    if (kIsWeb) {
      final box = await hiveBox;
      await box.delete('monitoreo_$id');
      await box.delete('respuestas_$id');
      return 1;
    } else {
      final db = await database;
      return await db!.update(
        'monitoreos',
        {'sincronizado': 1},
        where: 'id = ?',
        whereArgs: [id],
      );
    }
  }

  // ================ ESTADÍSTICAS ================
  Future<Map<String, dynamic>> getEstadisticas() async {
    if (kIsWeb) {
      final box = await hiveBox;
      return {
        'total_apiarios': box.keys
            .where((k) => k.toString().startsWith('apiario_'))
            .length,
        'total_colmenas': box.keys
            .where((k) => k.toString().startsWith('colmena_'))
            .length,
        'total_monitoreos': box.keys
            .where((k) => k.toString().startsWith('monitoreo_'))
            .length,
        'monitoreos_pendientes': box.keys
            .where((k) => k.toString().startsWith('monitoreo_'))
            .length,
      };
    } else {
      final db = await database;
      final apiariosCount =
          Sqflite.firstIntValue(
            await db!.rawQuery('SELECT COUNT(*) FROM apiarios'),
          ) ??
          0;
      final colmenasCount =
          Sqflite.firstIntValue(
            await db.rawQuery('SELECT COUNT(*) FROM colmenas WHERE activa = 1'),
          ) ??
          0;
      final monitoreosCount =
          Sqflite.firstIntValue(
            await db.rawQuery('SELECT COUNT(*) FROM monitoreos'),
          ) ??
          0;
      final pendientesCount =
          Sqflite.firstIntValue(
            await db.rawQuery(
              'SELECT COUNT(*) FROM monitoreos WHERE sincronizado = 0',
            ),
          ) ??
          0;

      return {
        'total_apiarios': apiariosCount,
        'total_colmenas': colmenasCount,
        'total_monitoreos': monitoreosCount,
        'monitoreos_pendientes': pendientesCount,
      };
    }
  }

  Future<void> close() async {
    if (kIsWeb) {
      final box = await hiveBox;
      await box.close();
      _hiveBox = null;
    } else {
      final db = _database;
      if (db != null) {
        await db.close();
        _database = null;
      }
    }
  }
}
