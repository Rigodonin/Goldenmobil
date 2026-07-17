import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/calculadora_produccion.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  List<dynamic> _todosLosRegistros = [];
  List<dynamic> _registrosFiltrados = [];
  bool _isLoadingDashboard = true;

  // VARIABLES PARA FILTROS
  String _tipoFiltro = 'Operador';
  String _periodoFiltro = 'Todos';
  String _operadorFiltro = 'Todos';
  String _turnoFiltro = 'Todos';
  String _cumplimientoFiltro = 'Todos';
  String _registroFiltro = 'Todos';
  final _busquedaController = TextEditingController();
  final _fechaInicioController = TextEditingController();
  final _fechaFinController = TextEditingController();

  // Variables para los Dropdowns dinámicos
  List<String> _listaOperadores = [];
  String? _operadorSeleccionadoFiltro;
  final Set<String> _turnosSeleccionadosFiltro = {'A'};

  @override
  void initState() {
    super.initState();
    _cargarDashboard();
  }

  @override
  void dispose() {
    _busquedaController.dispose();
    _fechaInicioController.dispose();
    _fechaFinController.dispose();
    super.dispose();
  }

  Future<void> _cargarDashboard() async {
    setState(() => _isLoadingDashboard = true);
    try {
      final response = await Supabase.instance.client
          .from('registros_produccion')
          .select('*, perfiles(nombre_completo, turno_laboral)')
          .order('fecha', ascending: false);

      final operadoresResponse = await Supabase.instance.client
          .from('perfiles')
          .select('nombre_completo')
          .eq('rol', 'operador');

      final Set<String> opsUnicos = {};
      for (var op in operadoresResponse) {
        if (op['nombre_completo'] != null) {
          opsUnicos.add(op['nombre_completo']);
        }
      }

      setState(() {
        _todosLosRegistros = response;
        _registrosFiltrados = response;
        _listaOperadores = opsUnicos.toList();
        _operadorSeleccionadoFiltro = _listaOperadores.isNotEmpty
            ? _listaOperadores.first
            : null;
        _operadorFiltro = 'Todos';
        _isLoadingDashboard = false;
      });
    } catch (e) {
      setState(() => _isLoadingDashboard = false);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error al cargar datos: $e')));
      }
    }
  }

  Future<void> _seleccionarFecha(
    BuildContext context,
    TextEditingController controlador,
  ) async {
    final DateTime? seleccion = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF1E2265),
              onPrimary: Colors.white,
              onSurface: Colors.black,
            ),
          ),
          child: child!,
        );
      },
    );

    if (seleccion != null) {
      setState(() {
        controlador.text =
            "${seleccion.year}-${seleccion.month.toString().padLeft(2, '0')}-${seleccion.day.toString().padLeft(2, '0')}";
      });
    }
  }

  void _aplicarFiltro() {
    final rango = _rangoFechasFiltro();
    setState(() {
      _registrosFiltrados = _todosLosRegistros.where((reg) {
        return _cumplePeriodo(reg, rango) &&
            _cumpleOperador(reg) &&
            _cumpleTurno(reg) &&
            _cumpleCumplimiento(reg) &&
            _cumpleRegistro(reg);
      }).toList();
    });
  }

  void _limpiarFiltros() {
    setState(() {
      _tipoFiltro = 'Operador';
      _periodoFiltro = 'Todos';
      _operadorFiltro = 'Todos';
      _turnoFiltro = 'Todos';
      _cumplimientoFiltro = 'Todos';
      _registroFiltro = 'Todos';
      _busquedaController.clear();
      _fechaInicioController.clear();
      _fechaFinController.clear();
      _operadorSeleccionadoFiltro = _listaOperadores.isNotEmpty
          ? _listaOperadores.first
          : null;
      _turnosSeleccionadosFiltro
        ..clear()
        ..add('A');
      _registrosFiltrados = _todosLosRegistros;
    });
  }

  String _limpiarCeldaExcel(dynamic valor) {
    return (valor ?? '')
        .toString()
        .replaceAll(RegExp(r'[\t\r\n]+'), ' ')
        .trim();
  }

  double _totalRegistro(dynamic reg) {
    return ((reg['t1_metros'] ?? 0) +
            (reg['t2_metros'] ?? 0) +
            (reg['t3_metros'] ?? 0) +
            (reg['t4_metros'] ?? 0))
        .toDouble();
  }

  DateTime? _fechaRegistro(dynamic reg) {
    final fecha = reg['fecha']?.toString();
    if (fecha == null || fecha.isEmpty) return null;
    return DateTime.tryParse(fecha);
  }

  String _formatearFecha(DateTime fecha) {
    return "${fecha.year}-${fecha.month.toString().padLeft(2, '0')}-${fecha.day.toString().padLeft(2, '0')}";
  }

  Map<String, String>? _rangoFechasFiltro() {
    final hoy = DateTime.now();
    DateTime inicio;
    DateTime fin;

    switch (_periodoFiltro) {
      case 'Hoy':
        inicio = DateTime(hoy.year, hoy.month, hoy.day);
        fin = inicio;
        break;
      case 'Ayer':
        inicio = DateTime(hoy.year, hoy.month, hoy.day).subtract(
          const Duration(days: 1),
        );
        fin = inicio;
        break;
      case 'Esta quincena':
        if (hoy.day <= 15) {
          inicio = DateTime(hoy.year, hoy.month, 1);
          fin = DateTime(hoy.year, hoy.month, 15);
        } else {
          inicio = DateTime(hoy.year, hoy.month, 16);
          fin = DateTime(hoy.year, hoy.month + 1, 0);
        }
        break;
      case 'Quincena anterior':
        if (hoy.day <= 15) {
          final mesAnterior = DateTime(hoy.year, hoy.month, 0);
          inicio = DateTime(mesAnterior.year, mesAnterior.month, 16);
          fin = mesAnterior;
        } else {
          inicio = DateTime(hoy.year, hoy.month, 1);
          fin = DateTime(hoy.year, hoy.month, 15);
        }
        break;
      case 'Este mes':
        inicio = DateTime(hoy.year, hoy.month, 1);
        fin = DateTime(hoy.year, hoy.month + 1, 0);
        break;
      case 'Rango personalizado':
        if (_fechaInicioController.text.isEmpty ||
            _fechaFinController.text.isEmpty) {
          return null;
        }
        return {
          'inicio': _fechaInicioController.text,
          'fin': _fechaFinController.text,
        };
      default:
        return null;
    }

    return {'inicio': _formatearFecha(inicio), 'fin': _formatearFecha(fin)};
  }

  bool _cumplePeriodo(dynamic reg, Map<String, String>? rango) {
    if (rango == null) return true;
    final fecha = reg['fecha']?.toString() ?? '';
    return fecha.compareTo(rango['inicio']!) >= 0 &&
        fecha.compareTo(rango['fin']!) <= 0;
  }

  bool _cumpleOperador(dynamic reg) {
    if (_operadorFiltro == 'Todos') return true;
    final nombre = reg['perfiles']?['nombre_completo'] ?? '';
    return nombre == _operadorFiltro;
  }

  bool _cumpleTurno(dynamic reg) {
    if (_turnoFiltro == 'Todos') return true;
    final turno = reg['perfiles']?['turno_laboral'] ?? '';
    return turno == _turnoFiltro;
  }

  double _porcentajeRegistro(dynamic reg) {
    final fecha = _fechaRegistro(reg);
    final turno = reg['perfiles']?['turno_laboral']?.toString() ?? '';
    if (fecha == null || turno.isEmpty) return 0;
    final meta = CalculadoraProduccion.calcularMetaDiariaMetros(turno, fecha);
    return meta <= 0 ? 0 : (_totalRegistro(reg) / meta) * 100;
  }

  bool _cumpleCumplimiento(dynamic reg) {
    if (_cumplimientoFiltro == 'Todos') return true;
    final porcentaje = _porcentajeRegistro(reg);
    switch (_cumplimientoFiltro) {
      case 'Bajo 80%':
        return porcentaje < 80;
      case '80% a 99%':
        return porcentaje >= 80 && porcentaje < 100;
      case '100% o mas':
        return porcentaje >= 100;
      default:
        return true;
    }
  }

  bool _cumpleRegistro(dynamic reg) {
    final notas = (reg['notas'] ?? '').toString().trim();
    final tieneMaquinaEnCero =
        (reg['t1_metros'] ?? 0) == 0 ||
        (reg['t2_metros'] ?? 0) == 0 ||
        (reg['t3_metros'] ?? 0) == 0 ||
        (reg['t4_metros'] ?? 0) == 0;

    switch (_registroFiltro) {
      case 'Con notas':
        return notas.isNotEmpty;
      case 'Sin notas':
        return notas.isEmpty;
      case 'Maquinas en 0':
        return tieneMaquinaEnCero;
      default:
        return true;
    }
  }

  double _calcularMetaPeriodo(String turno, DateTime inicio, DateTime fin) {
    double meta = 0;
    DateTime dia = DateTime(inicio.year, inicio.month, inicio.day);
    final ultimoDia = DateTime(fin.year, fin.month, fin.day);

    while (!dia.isAfter(ultimoDia)) {
      meta += CalculadoraProduccion.calcularMetaDiariaMetros(turno, dia);
      dia = dia.add(const Duration(days: 1));
    }

    return meta;
  }

  List<Map<String, dynamic>> _rankingOperadores() {
    final agrupado = <String, Map<String, dynamic>>{};

    for (final reg in _registrosFiltrados) {
      final nombre = reg['perfiles']?['nombre_completo'] ?? 'N/A';
      final turno = reg['perfiles']?['turno_laboral'] ?? '-';
      final fecha = _fechaRegistro(reg);

      final item = agrupado.putIfAbsent(
        nombre,
        () => {
          'nombre': nombre,
          'turno': turno,
          'total': 0.0,
          'inicio': fecha,
          'fin': fecha,
        },
      );

      item['total'] = (item['total'] as double) + _totalRegistro(reg);
      if (fecha != null) {
        final inicioActual = item['inicio'] as DateTime?;
        final finActual = item['fin'] as DateTime?;
        if (inicioActual == null || fecha.isBefore(inicioActual)) {
          item['inicio'] = fecha;
        }
        if (finActual == null || fecha.isAfter(finActual)) {
          item['fin'] = fecha;
        }
      }
    }

    final rangoFiltro = _rangoFechasFiltro();
    final inicioFiltro = rangoFiltro == null
        ? null
        : DateTime.tryParse(rangoFiltro['inicio']!);
    final finFiltro = rangoFiltro == null
        ? null
        : DateTime.tryParse(rangoFiltro['fin']!);

    for (final item in agrupado.values) {
      final inicio = inicioFiltro ?? (item['inicio'] as DateTime?);
      final fin = finFiltro ?? (item['fin'] as DateTime?);
      final turno = item['turno']?.toString() ?? '-';
      final total = item['total'] as double;
      final meta = inicio == null || fin == null
          ? 0.0
          : _calcularMetaPeriodo(turno, inicio, fin);

      item['meta'] = meta;
      item['porcentaje'] = meta <= 0 ? 0.0 : (total / meta) * 100;
    }

    final ranking = agrupado.values.toList();
    ranking.sort(
      (a, b) => (b['total'] as double).compareTo(a['total'] as double),
    );
    return ranking;
  }

  Widget _buildSelectorTurnos() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: ['A', 'B', 'C'].map((turno) {
        final seleccionado = _turnosSeleccionadosFiltro.contains(turno);
        return FilterChip(
          label: Text('Turno $turno'),
          selected: seleccionado,
          onSelected: (valor) {
            setState(() {
              if (valor) {
                _turnosSeleccionadosFiltro.add(turno);
              } else if (_turnosSeleccionadosFiltro.length > 1) {
                _turnosSeleccionadosFiltro.remove(turno);
              }
            });
          },
        );
      }).toList(),
    );
  }

  Widget _buildRankingOperadores() {
    final ranking = _rankingOperadores();

    return Card(
      elevation: 1,
      color: const Color(0xFFFAFAFD),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: Color(0xFFE2E0E6)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.leaderboard, color: Color(0xFF1E2265), size: 22),
                SizedBox(width: 8),
                Text(
                  'Ranking',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (ranking.isEmpty)
              const Text(
                'Sin registros filtrados.',
                style: TextStyle(color: Colors.black54),
              )
            else
              Expanded(
                child: ListView.separated(
                  itemCount: ranking.length,
                  separatorBuilder: (_, index) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final item = ranking[index];
                    final nombre = item['nombre']?.toString() ?? 'N/A';
                    final turno = item['turno']?.toString() ?? '-';
                    final total = item['total'] as double;
                    final porcentaje = item['porcentaje'] as double;
                    final progreso = (porcentaje / 100).clamp(0.0, 1.0);
                    final colorPorcentaje = porcentaje >= 80
                        ? Colors.green
                        : porcentaje >= 70
                        ? Colors.amber.shade700
                        : Colors.redAccent;

                    return Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFE7E6F0)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CircleAvatar(
                            radius: 16,
                            backgroundColor: const Color(0xFF1E2265),
                            foregroundColor: Colors.white,
                            child: Text(
                              '${index + 1}',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  nombre,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 6,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFDBDBF0),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        'Turno $turno',
                                        style: const TextStyle(
                                          color: Color(0xFF1E2265),
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      '${total.toStringAsFixed(0)} mts',
                                      style: const TextStyle(
                                        color: Colors.black87,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: LinearProgressIndicator(
                                    value: progreso,
                                    minHeight: 7,
                                    backgroundColor: const Color(0xFFEDECF4),
                                    color: colorPorcentaje,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
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
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildRegistrosConRanking() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          flex: 3,
          child: ListView.builder(
            itemCount: _registrosFiltrados.length,
            itemBuilder: (context, index) {
              final reg = _registrosFiltrados[index];
              final nombre = reg['perfiles']?['nombre_completo'] ?? 'N/A';
              final turno = reg['perfiles']?['turno_laboral'] ?? '-';
              final total = _totalRegistro(reg);

              return Card(
                child: ListTile(
                  title: Text(
                    '$nombre (Turno $turno) - ${reg['fecha']}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    'T1:${reg['t1_metros']} T2:${reg['t2_metros']} T3:${reg['t3_metros']} T4:${reg['t4_metros']}\nNotas: ${reg['notas']}',
                  ),
                  trailing: Text(
                    '${total.toInt()}m',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1E2265),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(width: 420, child: _buildRankingOperadores()),
      ],
    );
  }

  Future<void> _copiarAExcel() async {
    if (_registrosFiltrados.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay registros para copiar')),
      );
      return;
    }

    final filas = <List<String>>[
      ['Fecha', 'Operador', 'Turno', 'T1', 'T2', 'T3', 'T4', 'Total', 'Notas'],
    ];

    for (final reg in _registrosFiltrados) {
      final nombre = reg['perfiles']?['nombre_completo'] ?? 'N/A';
      final turno = reg['perfiles']?['turno_laboral'] ?? '-';
      final t1 = reg['t1_metros'] ?? 0;
      final t2 = reg['t2_metros'] ?? 0;
      final t3 = reg['t3_metros'] ?? 0;
      final t4 = reg['t4_metros'] ?? 0;
      final total = (t1 ?? 0) + (t2 ?? 0) + (t3 ?? 0) + (t4 ?? 0);

      filas.add([
        _limpiarCeldaExcel(reg['fecha']),
        _limpiarCeldaExcel(nombre),
        _limpiarCeldaExcel(turno),
        _limpiarCeldaExcel(t1),
        _limpiarCeldaExcel(t2),
        _limpiarCeldaExcel(t3),
        _limpiarCeldaExcel(t4),
        _limpiarCeldaExcel(total),
        _limpiarCeldaExcel(reg['notas']),
      ]);
    }

    final texto = filas.map((fila) => fila.join('\t')).join('\n');
    await Clipboard.setData(ClipboardData(text: texto));

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${_registrosFiltrados.length} registros copiados para Excel',
        ),
      ),
    );
  }

  Future<void> _cerrarSesion() async {
    await Supabase.instance.client.auth.signOut();
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
  }

  Future<void> _mostrarDialogoNuevoOperador() async {
    final nombreCtrl = TextEditingController();
    final usuarioCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    String turnoSel = 'A';
    bool isLoading = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            final double keyboardPadding = MediaQuery.of(
              context,
            ).viewInsets.bottom;

            return Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: EdgeInsets.only(
                  top: 20,
                  left: 20,
                  right: 20,
                  bottom: 20 + keyboardPadding,
                ),
                constraints: const BoxConstraints(maxWidth: 400),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Dar de Alta Operador',
                        style: TextStyle(
                          color: Color(0xFF1E2265),
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: nombreCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Nombre Completo',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: usuarioCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Usuario / Nómina',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: passCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Contraseña temporal (mín. 6)',
                          border: OutlineInputBorder(),
                        ),
                        obscureText: true,
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: turnoSel,
                        decoration: const InputDecoration(
                          labelText: 'Turno',
                          border: OutlineInputBorder(),
                        ),
                        items: ['A', 'B', 'C']
                            .map(
                              (t) => DropdownMenuItem(
                                value: t,
                                child: Text('Turno $t'),
                              ),
                            )
                            .toList(),
                        onChanged: (val) =>
                            setStateDialog(() => turnoSel = val!),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: isLoading
                                ? null
                                : () => Navigator.pop(ctx),
                            child: const Text(
                              'Cancelar',
                              style: TextStyle(color: Colors.red),
                            ),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            onPressed: isLoading
                                ? null
                                : () async {
                                    if (nombreCtrl.text.trim().isEmpty ||
                                        usuarioCtrl.text.trim().isEmpty ||
                                        passCtrl.text.trim().isEmpty) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'Por favor llena todos los campos',
                                          ),
                                          backgroundColor: Colors.orange,
                                        ),
                                      );
                                      return;
                                    }
                                    if (passCtrl.text.trim().length < 6) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'La contraseña debe tener al menos 6 caracteres',
                                          ),
                                          backgroundColor: Colors.orange,
                                        ),
                                      );
                                      return;
                                    }

                                    setStateDialog(() => isLoading = true);
                                    try {
                                      final correoGenerado =
                                          '${usuarioCtrl.text.trim().toLowerCase()}@gs.com';

                                      // Registro limpio utilizando la instancia global inicializada
                                      final res = await Supabase
                                          .instance
                                          .client
                                          .auth
                                          .signUp(
                                            email: correoGenerado,
                                            password: passCtrl.text.trim(),
                                          );

                                      if (res.user != null) {
                                        // Inserción o actualización en cascada del perfil creado
                                        await Supabase.instance.client
                                            .from('perfiles')
                                            .upsert({
                                              'id': res.user!.id,
                                              'nombre_completo': nombreCtrl.text
                                                  .trim(),
                                              'turno_laboral': turnoSel,
                                              'rol': 'operador',
                                            });
                                      }

                                      if (mounted) {
                                        Navigator.pop(ctx);
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          const SnackBar(
                                            content: Text(
                                              'Operador creado con éxito',
                                            ),
                                            backgroundColor: Colors.green,
                                          ),
                                        );
                                        _cargarDashboard();
                                      }
                                    } catch (e) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            'Error: ${e.toString().replaceAll("AuthApiError:", "")}',
                                          ),
                                          backgroundColor: Colors.red,
                                        ),
                                      );
                                    } finally {
                                      if (mounted)
                                        setStateDialog(() => isLoading = false);
                                    }
                                  },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF1E2265),
                              foregroundColor: Colors.white,
                            ),
                            child: isLoading
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Text('Guardar'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  InputDecoration _decoracionFiltro(String label) {
    return InputDecoration(
      labelText: label,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      isDense: true,
    );
  }

  Widget _buildDropdownFiltro({
    required String label,
    required String value,
    required List<String> opciones,
    required ValueChanged<String?> onChanged,
  }) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      decoration: _decoracionFiltro(label),
      items: opciones
          .map((opcion) => DropdownMenuItem(value: opcion, child: Text(opcion)))
          .toList(),
      onChanged: onChanged,
    );
  }

  Widget _buildFechaFiltro({
    required String label,
    required TextEditingController controller,
  }) {
    return TextField(
      controller: controller,
      readOnly: true,
      decoration: _decoracionFiltro(label).copyWith(
        suffixIcon: const Icon(Icons.calendar_month),
      ),
      onTap: () => _seleccionarFecha(context, controller),
    );
  }

  Widget _buildPanelFiltros() {
    final operadores = ['Todos', ..._listaOperadores];

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildDropdownFiltro(
                label: 'Rango de fecha',
                value: _periodoFiltro,
                opciones: const [
                  'Todos',
                  'Hoy',
                  'Ayer',
                  'Esta quincena',
                  'Quincena anterior',
                  'Este mes',
                  'Rango personalizado',
                ],
                onChanged: (val) {
                  if (val == null) return;
                  setState(() {
                    _periodoFiltro = val;
                    if (val != 'Rango personalizado') {
                      _fechaInicioController.clear();
                      _fechaFinController.clear();
                    }
                  });
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildDropdownFiltro(
                label: 'Operador',
                value: operadores.contains(_operadorFiltro)
                    ? _operadorFiltro
                    : 'Todos',
                opciones: operadores,
                onChanged: (val) =>
                    setState(() => _operadorFiltro = val ?? 'Todos'),
              ),
            ),
          ],
        ),
        if (_periodoFiltro == 'Rango personalizado') ...[
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _buildFechaFiltro(
                  label: 'Desde',
                  controller: _fechaInicioController,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildFechaFiltro(
                  label: 'Hasta',
                  controller: _fechaFinController,
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _buildDropdownFiltro(
                label: 'Turno',
                value: _turnoFiltro,
                opciones: const ['Todos', 'A', 'B', 'C'],
                onChanged: (val) =>
                    setState(() => _turnoFiltro = val ?? 'Todos'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildDropdownFiltro(
                label: 'Cumplimiento',
                value: _cumplimientoFiltro,
                opciones: const ['Todos', 'Bajo 80%', '80% a 99%', '100% o mas'],
                onChanged: (val) =>
                    setState(() => _cumplimientoFiltro = val ?? 'Todos'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildDropdownFiltro(
                label: 'Registros',
                value: _registroFiltro,
                opciones: const [
                  'Todos',
                  'Con notas',
                  'Sin notas',
                  'Maquinas en 0',
                ],
                onChanged: (val) =>
                    setState(() => _registroFiltro = val ?? 'Todos'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Panel de Administrador',
          style: TextStyle(color: Colors.white),
        ),
        backgroundColor: const Color(0xFF1E2265),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            tooltip: 'Cerrar sesion',
            onPressed: _cerrarSesion,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  children: [
                    _buildPanelFiltros(),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        ElevatedButton.icon(
                          onPressed: _aplicarFiltro,
                          icon: const Icon(Icons.search),
                          label: const Text('Aplicar filtros'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1E2265),
                            foregroundColor: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: _limpiarFiltros,
                          icon: const Icon(Icons.filter_alt_off),
                          label: const Text('Limpiar'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: Wrap(
                spacing: 10,
                children: [
                  ElevatedButton.icon(
                    onPressed: _mostrarDialogoNuevoOperador,
                    icon: const Icon(Icons.person_add),
                    label: const Text('Nuevo Operador'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: _copiarAExcel,
                    icon: const Icon(Icons.copy),
                    label: const Text('Copiar a Excel'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1E2265),
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _isLoadingDashboard
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: Color(0xFF1E2265),
                      ),
                    )
                  : _buildRegistrosConRanking(),
            ),
          ],
        ),
      ),
    );
  }
}
