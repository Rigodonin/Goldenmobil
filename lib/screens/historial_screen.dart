import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/calculadora_produccion.dart';

class HistorialScreen extends StatefulWidget {
  const HistorialScreen({super.key});

  @override
  State<HistorialScreen> createState() => _HistorialScreenState();
}

class _HistorialScreenState extends State<HistorialScreen> {
  late Future<Map<String, dynamic>> _datosFuture;

  @override
  void initState() {
    super.initState();
    _datosFuture = _cargarDatos();
  }

  void _recargar() {
    setState(() => _datosFuture = _cargarDatos());
  }

  Map<String, String?> _obtenerRangoDesdePeriodoOFecha(
    dynamic periodo,
    dynamic fechaCierre,
  ) {
    try {
      if (periodo != null) {
        final str = periodo.toString();
        final regExp = RegExp(r'\d{4}-\d{2}-\d{2}');
        final matches = regExp.allMatches(str).map((m) => m.group(0)).toList();
        if (matches.length >= 2) {
          return {'inicio': matches[0], 'fin': matches[1]};
        }
      }
    } catch (_) {}

    try {
      if (fechaCierre != null) {
        final fecha = DateTime.parse(fechaCierre.toString());
        DateTime inicio;
        DateTime fin;
        if (fecha.day <= 15) {
          inicio = DateTime(fecha.year, fecha.month, 1);
          fin = DateTime(fecha.year, fecha.month, 15);
        } else {
          inicio = DateTime(fecha.year, fecha.month, 16);
          fin = DateTime(fecha.year, fecha.month + 1, 0);
        }
        return {
          'inicio': _formatearFecha(inicio),
          'fin': _formatearFecha(fin),
        };
      }
    } catch (_) {}

    return {'inicio': null, 'fin': null};
  }

  String _formatearFecha(DateTime fecha) {
    return '${fecha.year}-${fecha.month.toString().padLeft(2, '0')}-${fecha.day.toString().padLeft(2, '0')}';
  }

  double _calcularMetaHistorica(String turno, String inicioStr, String finStr) {
    try {
      DateTime current = DateTime.parse(inicioStr);
      DateTime fFin = DateTime.parse(finStr);
      double metaTotal = 0.0;

      while (!current.isAfter(fFin)) {
        metaTotal += CalculadoraProduccion.calcularMetaDiariaMetros(
          turno,
          current,
        );
        current = current.add(const Duration(days: 1));
      }
      return metaTotal;
    } catch (_) {
      return 0.0;
    }
  }

  double _metaFijaPeriodo(
    dynamic item,
    String turno,
    Map<String, String?> rango,
  ) {
    final metaArchivada = (item['meta_metros'] as num?)?.toDouble() ?? 0.0;
    if (metaArchivada > 0) return metaArchivada;

    if (rango['inicio'] != null && rango['fin'] != null) {
      return _calcularMetaHistorica(turno, rango['inicio']!, rango['fin']!);
    }
    return 0.0;
  }

  double _totalRegistro(dynamic reg) {
    return ((reg['t1_metros'] ?? 0) +
            (reg['t2_metros'] ?? 0) +
            (reg['t3_metros'] ?? 0) +
            (reg['t4_metros'] ?? 0))
        .toDouble();
  }

  double _totalRegistros(List<dynamic> registros) {
    double total = 0;
    for (final reg in registros) {
      total += _totalRegistro(reg);
    }
    return total;
  }

  String _metrosEnteros(dynamic valor) {
    final numero = valor is num
        ? valor.toDouble()
        : double.tryParse(valor?.toString() ?? '') ?? 0;
    return numero.round().toString();
  }

  Color _colorPorcentaje(double porcentaje) {
    if (porcentaje >= 100) return Colors.green;
    if (porcentaje >= 80) return Colors.orange;
    if (porcentaje > 0) return Colors.red;
    return Colors.grey;
  }

  InputDecoration _decoracionCampo(String label) {
    return InputDecoration(
      labelText: label,
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFFE2E0E6)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFF1E2265), width: 1.4),
      ),
    );
  }

  Future<Map<String, dynamic>> _cargarDatos() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) throw Exception('Usuario no autenticado');

    final perfil = await Supabase.instance.client
        .from('perfiles')
        .select('turno_laboral')
        .eq('id', user.id)
        .single();

    final historial = await Supabase.instance.client
        .from('historial_quincenas')
        .select()
        .eq('operador_id', user.id)
        .order('fecha_cierre', ascending: false);

    return {
      'turno': perfil['turno_laboral'] ?? 'A',
      'historial': historial as List<dynamic>,
      'user_id': user.id,
    };
  }

  Future<List<dynamic>> _cargarRegistrosPeriodo(
    String userId,
    Map<String, String?> rango,
  ) async {
    if (rango['inicio'] == null || rango['fin'] == null) return [];

    final res = await Supabase.instance.client
        .from('registros_produccion')
        .select()
        .eq('operador_id', userId)
        .gte('fecha', rango['inicio']!)
        .lte('fecha', rango['fin']!)
        .order('fecha', ascending: false);
    return res as List<dynamic>;
  }

  Future<void> _editarRegistro(Map<String, dynamic> reg) async {
    final controllers = [
      TextEditingController(text: _metrosEnteros(reg['t1_metros'])),
      TextEditingController(text: _metrosEnteros(reg['t2_metros'])),
      TextEditingController(text: _metrosEnteros(reg['t3_metros'])),
      TextEditingController(text: _metrosEnteros(reg['t4_metros'])),
    ];
    final notasController = TextEditingController(
      text: (reg['notas'] ?? '').toString(),
    );

    try {
      final guardar = await showDialog<bool>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: Text('Editar registro ${reg['fecha']}'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: controllers[0],
                          decoration: _decoracionCampo('Primer Maquina'),
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: controllers[1],
                          decoration: _decoracionCampo('Segunda Maquina'),
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: controllers[2],
                          decoration: _decoracionCampo('Tercera Maquina'),
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: controllers[3],
                          decoration: _decoracionCampo('Cuarta Maquina'),
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: notasController,
                    decoration: _decoracionCampo('Notas / Observaciones'),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Guardar'),
              ),
            ],
          );
        },
      );

      if (guardar != true) return;

      await Supabase.instance.client
          .from('registros_produccion')
          .update({
            't1_metros': double.tryParse(controllers[0].text) ?? 0,
            't2_metros': double.tryParse(controllers[1].text) ?? 0,
            't3_metros': double.tryParse(controllers[2].text) ?? 0,
            't4_metros': double.tryParse(controllers[3].text) ?? 0,
            'notas': notasController.text,
          })
          .eq('id', reg['id']);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Registro actualizado')),
      );
      _recargar();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al actualizar: $e')),
      );
    } finally {
      for (final controller in controllers) {
        controller.dispose();
      }
      notasController.dispose();
    }
  }

  String _textoCompartirQuincena({
    required dynamic item,
    required List<dynamic> registros,
    required double totalMetros,
    required double metaPeriodo,
    required double porcentaje,
  }) {
    final buffer = StringBuffer();
    buffer.writeln('Historial de quincena');
    buffer.writeln('Periodo: ${item['periodo']}');
    buffer.writeln('Cerrada el: ${item['fecha_cierre']}');
    buffer.writeln('Total metros: ${totalMetros.toStringAsFixed(0)}m');
    buffer.writeln('Meta fija: ${metaPeriodo.toStringAsFixed(0)}m');
    buffer.writeln('Porcentaje: ${porcentaje.toStringAsFixed(1)}%');
    buffer.writeln('');
    buffer.writeln('Registros:');

    for (final reg in registros) {
      final totalReg = _totalRegistro(reg);
      final notas = (reg['notas'] ?? '').toString().trim();
      buffer.writeln(
        '${reg['fecha']} - ${totalReg.toStringAsFixed(0)}m '
        '(M1:${_metrosEnteros(reg['t1_metros'])}m, '
        'M2:${_metrosEnteros(reg['t2_metros'])}m, '
        'M3:${_metrosEnteros(reg['t3_metros'])}m, '
        'M4:${_metrosEnteros(reg['t4_metros'])}m)',
      );
      if (notas.isNotEmpty) {
        buffer.writeln('Notas: $notas');
      }
    }

    return buffer.toString();
  }

  Future<void> _copiarHistorialQuincena({
    required dynamic item,
    required List<dynamic> registros,
    required double totalMetros,
    required double metaPeriodo,
    required double porcentaje,
  }) async {
    final texto = _textoCompartirQuincena(
      item: item,
      registros: registros,
      totalMetros: totalMetros,
      metaPeriodo: metaPeriodo,
      porcentaje: porcentaje,
    );

    await Clipboard.setData(ClipboardData(text: texto));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Historial copiado al portapapeles')),
    );
  }
  Widget _buildTarjetaQuincena({
    required dynamic item,
    required String turnoUsuario,
    required String userId,
  }) {
    final rango = _obtenerRangoDesdePeriodoOFecha(
      item['periodo'],
      item['fecha_cierre'],
    );
    final metaPeriodo = _metaFijaPeriodo(item, turnoUsuario, rango);

    return FutureBuilder<List<dynamic>>(
      future: _cargarRegistrosPeriodo(userId, rango),
      builder: (context, registrosSnapshot) {
        final cargando = registrosSnapshot.connectionState == ConnectionState.waiting;
        final registros = registrosSnapshot.data ?? const <dynamic>[];
        final totalMetros = registrosSnapshot.hasData
            ? _totalRegistros(registros)
            : (item['total_metros'] as num?)?.toDouble() ?? 0.0;
        final porcentaje = metaPeriodo <= 0 ? 0.0 : (totalMetros / metaPeriodo) * 100;
        final colorPorcentaje = _colorPorcentaje(porcentaje);

        return Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            side: const BorderSide(color: Color(0xFFE2E0E6)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: ExpansionTile(
            leading: const Icon(
              Icons.archive_outlined,
              color: Color(0xFF2E3192),
            ),
            title: Text('Cerrada el: ${item['fecha_cierre']}'),
            subtitle: Text('${item['periodo']}'),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${totalMetros.toStringAsFixed(0)} mts',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                if (cargando)
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else if (porcentaje > 0)
                  Text(
                    '${porcentaje.toStringAsFixed(1)}%',
                    style: TextStyle(
                      color: colorPorcentaje,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
              ],
            ),
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16.0,
                  vertical: 8.0,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Meta fija del periodo: ${metaPeriodo.toStringAsFixed(0)} mts',
                      style: const TextStyle(
                        color: Colors.black54,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        value: (porcentaje / 100).clamp(0.0, 1.0),
                        backgroundColor: Colors.grey.shade200,
                        color: colorPorcentaje,
                        minHeight: 6,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: cargando
                        ? null
                        : () => _copiarHistorialQuincena(
                              item: item,
                              registros: registros,
                              totalMetros: totalMetros,
                              metaPeriodo: metaPeriodo,
                              porcentaje: porcentaje,
                            ),
                    icon: const Icon(Icons.copy, size: 18),
                    label: const Text('Copiar historial'),
                  ),
                ),
              ),
              const Divider(height: 1),
              if (cargando)
                const Padding(
                  padding: EdgeInsets.all(12.0),
                  child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                )
              else if (registros.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(12.0),
                  child: Text(
                    'No se encontraron registros diarios detallados.',
                    style: TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                )
              else
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: registros.length,
                  itemBuilder: (context, idx) {
                    final reg = registros[idx];
                    final totalReg = _totalRegistro(reg);
                    final notas = (reg['notas'] ?? '').toString().trim();
                    return Container(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: ListTile(
                        dense: true,
                        title: Text(
                          'Fecha: ${reg['fecha']}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'T1:${_metrosEnteros(reg['t1_metros'])}m | T2:${_metrosEnteros(reg['t2_metros'])}m\nT3:${_metrosEnteros(reg['t3_metros'])}m | T4:${_metrosEnteros(reg['t4_metros'])}m',
                            ),
                            if (notas.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                'Notas: $notas',
                                style: const TextStyle(color: Colors.black54),
                              ),
                            ],
                          ],
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '${totalReg.toStringAsFixed(0)}m',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF1E2265),
                              ),
                            ),
                            IconButton(
                              tooltip: 'Editar registro',
                              icon: const Icon(Icons.edit, size: 20),
                              onPressed: () => _editarRegistro(
                                Map<String, dynamic>.from(reg as Map),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Historial de Quincenas'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _datosFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Text('Error al cargar historial: ${snapshot.error}'),
            );
          }

          final listaHistorial =
              snapshot.data?['historial'] as List<dynamic>? ?? [];
          final turnoUsuario = snapshot.data?['turno'] as String? ?? 'A';
          final userId = snapshot.data?['user_id'] as String;

          if (listaHistorial.isEmpty) {
            return const Center(
              child: Text('No hay cierres quincenales registrados aun.'),
            );
          }

          return RefreshIndicator(
            onRefresh: () async => _recargar(),
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: listaHistorial.length,
              itemBuilder: (context, i) {
                return _buildTarjetaQuincena(
                  item: listaHistorial[i],
                  turnoUsuario: turnoUsuario,
                  userId: userId,
                );
              },
            ),
          );
        },
      ),
    );
  }
}
