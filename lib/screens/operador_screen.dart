import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/calculadora_produccion.dart';

class OperadorScreen extends StatefulWidget {
  const OperadorScreen({super.key});

  @override
  State<OperadorScreen> createState() => _OperadorScreenState();
}

class _OperadorScreenState extends State<OperadorScreen> {
  final _notasController = TextEditingController();
  final List<TextEditingController> _telarControllers = List.generate(
    4,
    (_) => TextEditingController(),
  );

  String _nombreOperador = 'Cargando...';
  String _turnoLaboral = 'A';

  double _metrosTotalesQuincena = 0.0;
  double _metaQuincenaTotal = 0.0;
  double _metaRitmoActual = 0.0;

  DateTime _fechaSeleccionada = DateTime.now();
  String? _idRegistroEditando;
  List<dynamic> _historialQuincena = [];
  List<Map<String, dynamic>> _rankingQuincena = [];
  bool _isLoading = true;
  bool _isLoadingRanking = false;
  String _turnoFiltroRanking = 'Todos';
  String _periodoFiltroRanking = 'actual';
  int _porcentajeMetaSeleccionado = 80;

  int? _diasLVManuales;
  int? _diasSabadoManuales;

  @override
  void initState() {
    super.initState();
    _cargarDatosOperador();
  }

  @override
  void dispose() {
    _notasController.dispose();
    for (final controller in _telarControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _cargarDatosOperador() async {
    setState(() => _isLoading = true);
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;

      final perfil = await Supabase.instance.client
          .from('perfiles')
          .select('nombre_completo, turno_laboral')
          .eq('id', user.id)
          .single();

      if (!mounted) return;
      setState(() {
        _nombreOperador = perfil['nombre_completo'] ?? 'Operador';
        _turnoLaboral = perfil['turno_laboral'] ?? 'A';
      });

      await _archivarQuincenaAnteriorSiHaceFalta(user.id);
      await _cargarHistorial();
      await _cargarRankingQuincena();
    } catch (e) {
      debugPrint("Error cargando operador: $e");
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  bool _esTurnoNoche() => _turnoLaboral == 'C';

  DateTime _fechaOperativaQuincena() {
    final ahora = DateTime.now();
    if (_esTurnoNoche() && ahora.hour < 12) {
      return ahora.subtract(const Duration(days: 1));
    }
    return ahora;
  }

  Map<String, DateTime> _rangoQuincenaParaFecha(DateTime fecha) {
    if (fecha.day <= 15) {
      return {
        'inicio': DateTime(fecha.year, fecha.month, 1),
        'fin': DateTime(fecha.year, fecha.month, 15),
      };
    }

    return {
      'inicio': DateTime(fecha.year, fecha.month, 16),
      'fin': DateTime(fecha.year, fecha.month + 1, 0),
    };
  }

  Map<String, DateTime> _obtenerRangoQuincenaOperador() {
    return _rangoQuincenaParaFecha(_fechaOperativaQuincena());
  }

  double _calcularMetaQuincenaOperador() {
    final rango = _obtenerRangoQuincenaOperador();
    double metaTotal = 0;
    var dia = rango['inicio']!;

    while (!dia.isAfter(rango['fin']!)) {
      metaTotal += CalculadoraProduccion.calcularMetaDiariaMetros(
        _turnoLaboral,
        dia,
      );
      dia = dia.add(const Duration(days: 1));
    }

    final horasLV = _turnoLaboral == 'C' ? 9.0 : 7.5;
    final horasSab = _turnoLaboral == 'A'
        ? 7.5
        : (_turnoLaboral == 'B' ? 5.5 : 0.0);

    if (_diasLVManuales != null && _diasLVManuales! > 0) {
      metaTotal -=
          (CalculadoraProduccion.metaPorHora * 4 * horasLV) * _diasLVManuales!;
    }

    if (_diasSabadoManuales != null && _diasSabadoManuales! > 0) {
      metaTotal -= (CalculadoraProduccion.metaPorHora * 4 * horasSab) *
          _diasSabadoManuales!;
    }

    return metaTotal < 0 ? 0 : metaTotal;
  }

  Future<void> _cargarHistorial() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    final rangos = _obtenerRangoQuincenaOperador();
    final inicio =
        "${rangos['inicio']!.year}-${rangos['inicio']!.month.toString().padLeft(2, '0')}-${rangos['inicio']!.day.toString().padLeft(2, '0')}";
    final fin =
        "${rangos['fin']!.year}-${rangos['fin']!.month.toString().padLeft(2, '0')}-${rangos['fin']!.day.toString().padLeft(2, '0')}";

    final response = await Supabase.instance.client
        .from('registros_produccion')
        .select()
        .eq('operador_id', user.id)
        .gte('fecha', inicio)
        .lte('fecha', fin)
        .order('fecha', ascending: false);

    double sumatoria = 0;
    for (var r in response) {
      sumatoria +=
          (r['t1_metros'] ?? 0) +
          (r['t2_metros'] ?? 0) +
          (r['t3_metros'] ?? 0) +
          (r['t4_metros'] ?? 0);
    }

    if (!mounted) return;
    setState(() {
      _historialQuincena = response;
      _metrosTotalesQuincena = sumatoria;
      _calcularMetas();
    });
  }

  double _totalRegistro(dynamic reg) {
    return ((reg['t1_metros'] ?? 0) +
            (reg['t2_metros'] ?? 0) +
            (reg['t3_metros'] ?? 0) +
            (reg['t4_metros'] ?? 0))
        .toDouble();
  }

  double _calcularMetaRitmoQuincena(
    String turno,
    DateTime inicio,
    DateTime fin,
  ) {
    final hoy = DateTime.now();
    final ayer = hoy.subtract(const Duration(days: 1));
    final limite = ayer.isAfter(fin) ? fin : ayer;

    double meta = 0;
    DateTime dia = DateTime(inicio.year, inicio.month, inicio.day);
    final ultimoDia = DateTime(limite.year, limite.month, limite.day);

    while (!dia.isAfter(ultimoDia)) {
      meta += CalculadoraProduccion.calcularMetaDiariaMetros(turno, dia);
      dia = dia.add(const Duration(days: 1));
    }

    return meta;
  }

  String _clavePeriodoRanking(DateTime inicio, DateTime fin) {
    return '${_formatearFecha(inicio)}|${_formatearFecha(fin)}';
  }

  Map<String, DateTime> _rangoDesdeClaveRanking(String clave) {
    if (clave == 'actual') {
      return CalculadoraProduccion.obtenerRangoQuincenaActual();
    }

    final partes = clave.split('|');
    if (partes.length != 2) {
      return CalculadoraProduccion.obtenerRangoQuincenaActual();
    }

    final inicio = DateTime.tryParse(partes[0]);
    final fin = DateTime.tryParse(partes[1]);
    if (inicio == null || fin == null) {
      return CalculadoraProduccion.obtenerRangoQuincenaActual();
    }

    return {'inicio': inicio, 'fin': fin};
  }

  Map<String, DateTime> _quincenaAnteriorA(DateTime inicio) {
    if (inicio.day == 16) {
      return {
        'inicio': DateTime(inicio.year, inicio.month, 1),
        'fin': DateTime(inicio.year, inicio.month, 15),
      };
    }

    final mesAnterior = DateTime(inicio.year, inicio.month, 0);
    return {
      'inicio': DateTime(mesAnterior.year, mesAnterior.month, 16),
      'fin': mesAnterior,
    };
  }

  String _fechaCorta(DateTime fecha) {
    return '${fecha.day.toString().padLeft(2, '0')}/${fecha.month.toString().padLeft(2, '0')}/${fecha.year}';
  }

  List<Map<String, String>> _periodosRankingDisponibles() {
    final actual = CalculadoraProduccion.obtenerRangoQuincenaActual();
    final periodos = <Map<String, String>>[
      {
        'clave': 'actual',
        'label':
            'Actual (${_fechaCorta(actual['inicio']!)} - ${_fechaCorta(actual['fin']!)})',
      },
    ];

    var rango = _quincenaAnteriorA(actual['inicio']!);
    for (var i = 0; i < 6; i++) {
      periodos.add({
        'clave': _clavePeriodoRanking(rango['inicio']!, rango['fin']!),
        'label':
            '${_fechaCorta(rango['inicio']!)} - ${_fechaCorta(rango['fin']!)}',
      });
      rango = _quincenaAnteriorA(rango['inicio']!);
    }

    return periodos;
  }

  Future<void> _cargarRankingQuincena() async {
    setState(() => _isLoadingRanking = true);
    try {
      final rangos = _rangoDesdeClaveRanking(_periodoFiltroRanking);
      final inicio = _formatearFecha(rangos['inicio']!);
      final fin = _formatearFecha(rangos['fin']!);

      final response = await Supabase.instance.client
          .from('registros_produccion')
          .select('*, perfiles(nombre_completo, turno_laboral)')
          .gte('fecha', inicio)
          .lte('fecha', fin);

      final agrupado = <String, Map<String, dynamic>>{};
      for (final reg in response) {
        final perfil = reg['perfiles'];
        final nombre = perfil?['nombre_completo'] ?? 'N/A';
        final turno = perfil?['turno_laboral'] ?? '-';
        final item = agrupado.putIfAbsent(
          nombre,
          () => {'nombre': nombre, 'turno': turno, 'total': 0.0},
        );

        item['total'] = (item['total'] as double) + _totalRegistro(reg);
      }

      final ranking = agrupado.values.map((item) {
        final turno = item['turno']?.toString() ?? '-';
        final total = item['total'] as double;
        final metaRitmo = _calcularMetaRitmoQuincena(
          turno,
          rangos['inicio']!,
          rangos['fin']!,
        );
        return {
          ...item,
          'metaRitmo': metaRitmo,
          'porcentajeRitmo': metaRitmo <= 0 ? 0.0 : (total / metaRitmo) * 100,
        };
      }).toList();

      ranking.sort(
        (a, b) => (b['total'] as double).compareTo(a['total'] as double),
      );

      if (!mounted) return;
      setState(() => _rankingQuincena = ranking);
    } catch (e) {
      debugPrint("Error cargando ranking: $e");
    } finally {
      if (mounted) {
        setState(() => _isLoadingRanking = false);
      }
    }
  }

  String _formatearFecha(DateTime fecha) {
    return "${fecha.year}-${fecha.month.toString().padLeft(2, '0')}-${fecha.day.toString().padLeft(2, '0')}";
  }

  Map<String, DateTime> _obtenerRangoQuincenaAnterior() {
    final rangoActual = _obtenerRangoQuincenaOperador();
    return _quincenaAnteriorA(rangoActual['inicio']!);
  }

  Future<void> _archivarQuincenaAnteriorSiHaceFalta(String operadorId) async {
    final rango = _obtenerRangoQuincenaAnterior();
    final inicio = _formatearFecha(rango['inicio']!);
    final fin = _formatearFecha(rango['fin']!);
    final periodo = '$inicio al $fin';

    final historialExistente = await Supabase.instance.client
        .from('historial_quincenas')
        .select('id')
        .eq('operador_id', operadorId)
        .eq('periodo', periodo)
        .maybeSingle();

    if (historialExistente != null) return;

    final registros = await Supabase.instance.client
        .from('registros_produccion')
        .select('t1_metros, t2_metros, t3_metros, t4_metros')
        .eq('operador_id', operadorId)
        .gte('fecha', inicio)
        .lte('fecha', fin);

    if (registros.isEmpty) return;

    double totalMetros = 0;
    for (final registro in registros) {
      totalMetros +=
          (registro['t1_metros'] ?? 0) +
          (registro['t2_metros'] ?? 0) +
          (registro['t3_metros'] ?? 0) +
          (registro['t4_metros'] ?? 0);
    }

    double metaMetros = 0;
    DateTime dia = rango['inicio']!;
    while (!dia.isAfter(rango['fin']!)) {
      metaMetros += CalculadoraProduccion.calcularMetaDiariaMetros(
        _turnoLaboral,
        dia,
      );
      dia = dia.add(const Duration(days: 1));
    }
    final porcentajeCumplido = metaMetros <= 0
        ? 0
        : (totalMetros / metaMetros) * 100;

    await Supabase.instance.client.from('historial_quincenas').insert({
      'operador_id': operadorId,
      'fecha_cierre': _formatearFecha(DateTime.now()),
      'periodo': periodo,
      'total_metros': totalMetros,
      'meta_metros': metaMetros,
      'porcentaje_cumplido': porcentajeCumplido,
    });
  }

  void _calcularMetas() {
    double metaRitmo = 0.0;
    for (var r in _historialQuincena) {
      DateTime f = DateTime.parse(r['fecha']);
      metaRitmo += CalculadoraProduccion.calcularMetaDiariaMetros(
        _turnoLaboral,
        f,
      );
    }

    double metaTotal = _calcularMetaQuincenaOperador();
    setState(() {
      _metaRitmoActual = metaRitmo;
      _metaQuincenaTotal = metaTotal;
    });
  }

  double _calcularPorcentaje(double avance, double meta) {
    if (meta <= 0) return 0;
    return avance / meta;
  }

  List<double> _metasDiasLaboralesQuincena() {
    final rango = _obtenerRangoQuincenaOperador();
    var dia = rango['inicio']!;
    final fin = rango['fin']!;
    final metas = <double>[];

    while (!dia.isAfter(fin)) {
      final metaDia = CalculadoraProduccion.calcularMetaDiariaMetros(
        _turnoLaboral,
        dia,
      );
      if (metaDia > 0) metas.add(metaDia);
      dia = dia.add(const Duration(days: 1));
    }

    return metas;
  }

  int? _siguienteNumeroRegistroQuincena() {
    final totalDiasLaborales = _metasDiasLaboralesQuincena().length;
    final registrosActuales = _historialQuincena.length;

    if (registrosActuales >= totalDiasLaborales) return null;
    return registrosActuales + 1;
  }

  double _calcularMetaAcumuladaPorRegistros(int cantidadRegistros) {
    final metas = _metasDiasLaboralesQuincena();
    final limite = cantidadRegistros.clamp(0, metas.length);

    double meta = 0;
    for (var i = 0; i < limite; i++) {
      meta += metas[i];
    }

    return meta;
  }

  int _registrosParaCalculoMetaSeleccionada() {
    final totalDiasLaborales = _metasDiasLaboralesQuincena().length;
    final siguienteRegistro = _siguienteNumeroRegistroQuincena();

    if (totalDiasLaborales == 0) return 0;
    return siguienteRegistro ?? totalDiasLaborales;
  }

  double _metaObjetivoSeleccionada() {
    final registrosParaCalculo = _registrosParaCalculoMetaSeleccionada();
    if (registrosParaCalculo == 0) return 0;

    final metaAcumulada = _calcularMetaAcumuladaPorRegistros(
      registrosParaCalculo,
    );
    return metaAcumulada * (_porcentajeMetaSeleccionado / 100);
  }

  double _diferenciaMetaSeleccionada() {
    return _metaObjetivoSeleccionada() - _metrosTotalesQuincena;
  }

  double _metrosNecesariosParaMetaSeleccionada() {
    final diferencia = _diferenciaMetaSeleccionada();
    return diferencia < 0 ? 0 : diferencia;
  }

  double _metrosNecesariosPorMaquina() {
    return _metrosNecesariosParaMetaSeleccionada() / 4;
  }

  Color _colorPorcentaje(double porcentaje) {
    if (porcentaje >= 80) return Colors.green;
    if (porcentaje >= 70) return Colors.amber.shade700;
    return Colors.redAccent;
  }

  InputDecoration _decoracionCampo(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: const Color(0xFF1E2265)),
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

  String _metrosEnteros(dynamic valor) {
    final numero = valor is num
        ? valor.toDouble()
        : double.tryParse(valor?.toString() ?? '') ?? 0;
    return numero.round().toString();
  }

  Widget _buildBarraProgreso({
    required String titulo,
    required double avance,
    required double meta,
    required Color color,
  }) {
    final porcentaje = _calcularPorcentaje(avance, meta);
    final progresoBarra = porcentaje.clamp(0.0, 1.0);
    final porcentajeTexto = (porcentaje * 100).round().toString();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(titulo, style: const TextStyle(fontWeight: FontWeight.w600)),
            Text(
              '$porcentajeTexto%',
              style: TextStyle(color: color, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: progresoBarra,
            minHeight: 11,
            backgroundColor: const Color(0xFFEDECF4),
            color: color,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '${_metrosEnteros(avance)}m / ${_metrosEnteros(meta)}m',
          style: const TextStyle(fontSize: 12, color: Colors.black54),
        ),
      ],
    );
  }

  Widget _buildCalculadoraMetaDeseada() {
    final registrosParaCalculo = _registrosParaCalculoMetaSeleccionada();
    final diferencia = _diferenciaMetaSeleccionada();
    final metrosNecesarios = _metrosNecesariosParaMetaSeleccionada();
    final metrosPorMaquina = _metrosNecesariosPorMaquina();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2E0E6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DropdownButtonFormField<int>(
            initialValue: _porcentajeMetaSeleccionado,
            decoration: _decoracionCampo('Meta deseada', Icons.track_changes),
            items: const [70, 80, 90, 100]
                .map(
                  (porcentaje) => DropdownMenuItem<int>(
                    value: porcentaje,
                    child: Text('$porcentaje%'),
                  ),
                )
                .toList(),
            onChanged: (valor) {
              if (valor == null) return;
              setState(() => _porcentajeMetaSeleccionado = valor);
            },
          ),
          const SizedBox(height: 10),
          Text(
            registrosParaCalculo == 0
                ? 'No hay meta laboral para calcular este porcentaje.'
                : diferencia < 0
                    ? 'Ya superas el $_porcentajeMetaSeleccionado%; tu avance actual ya cubre ese porcentaje.'
                    : 'Para quedar en el $_porcentajeMetaSeleccionado% necesitas hacer ${_metrosEnteros(metrosPorMaquina)}m por maquina, ${_metrosEnteros(metrosNecesarios)}m entre las 4.',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1E2265),
            ),
          ),
        ],
      ),
    );
  }

  Map<String, dynamic> _datosRegistroActual(String operadorId, String fecha) {
    return {
      'operador_id': operadorId,
      'fecha': fecha,
      't1_metros': double.tryParse(_telarControllers[0].text) ?? 0,
      't2_metros': double.tryParse(_telarControllers[1].text) ?? 0,
      't3_metros': double.tryParse(_telarControllers[2].text) ?? 0,
      't4_metros': double.tryParse(_telarControllers[3].text) ?? 0,
      'notas': _notasController.text, // Mantenido fiel a tu columna de Supabase
    };
  }

  double _limiteMetrosPorMaquina() {
    return _turnoLaboral == 'C' ? 1620 : 1350;
  }

  bool _hayMaquinasVaciasOCero() {
    return _telarControllers.any((controller) {
      final texto = controller.text.trim();
      return texto.isEmpty || (double.tryParse(texto) ?? 0) == 0;
    });
  }

  String? _mensajeLimiteMetros() {
    final limite = _limiteMetrosPorMaquina();
    for (var i = 0; i < _telarControllers.length; i++) {
      final texto = _telarControllers[i].text.trim();
      if (texto.isEmpty) continue;

      final metros = double.tryParse(texto) ?? 0;
      if (metros > limite) {
        return 'La maquina ${i + 1} supera el limite de ${limite.toStringAsFixed(0)}m para el turno $_turnoLaboral.';
      }
    }

    return null;
  }

  Future<bool> _confirmarMaquinasVaciasOCero() async {
    if (!_hayMaquinasVaciasOCero()) return true;

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Confirmar registro'),
          content: const Text(
            'Una o mas maquinas estan vacias o en 0m. Seguro que quieres guardar asi?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Guardar asi'),
            ),
          ],
        );
      },
    );

    return confirmar == true;
  }

  Future<void> _guardarRegistro() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    final fechaElegida = await _seleccionarFechaParaGuardar();
    if (fechaElegida == null) return;

    if (!mounted) return;
    setState(() => _fechaSeleccionada = fechaElegida);

    final mensajeLimite = _mensajeLimiteMetros();
    if (mensajeLimite != null) {
      _mostrarSnack(mensajeLimite);
      return;
    }

    final continuarConCeros = await _confirmarMaquinasVaciasOCero();
    if (!continuarConCeros) return;

    final fecha = _formatearFecha(fechaElegida);
    final datos = _datosRegistroActual(user.id, fecha);

    try {
      final response = await Supabase.instance.client
          .from('registros_produccion')
          .select()
          .eq('operador_id', user.id)
          .eq('fecha', fecha);

      final registroExistente = response.isEmpty ? null : response.first;
      final idExistente = registroExistente?['id']?.toString();
      final esElMismoRegistro =
          _idRegistroEditando != null && idExistente == _idRegistroEditando;

      if (registroExistente != null && !esElMismoRegistro) {
        if (!mounted) return;
        final opcion = await _mostrarOpcionesRegistroExistente(fecha);

        if (opcion == 'reemplazar') {
          await Supabase.instance.client
              .from('registros_produccion')
              .update(datos)
              .eq('id', registroExistente['id']);
          _mostrarSnack('Registro reemplazado correctamente');
        } else if (opcion == 'editar_fecha') {
          await _guardarRegistro();
          return;
        } else {
          return;
        }
      } else if (_idRegistroEditando != null) {
        await Supabase.instance.client
            .from('registros_produccion')
            .update(datos)
            .eq('id', _idRegistroEditando!);
        _mostrarSnack('Registro actualizado correctamente');
      } else {
        await Supabase.instance.client
            .from('registros_produccion')
            .insert(datos);
        _mostrarSnack('Registro guardado correctamente');
      }

      _limpiarFormulario();
      await _cargarHistorial();
      _periodoFiltroRanking = 'actual';
      await _cargarRankingQuincena();
    } catch (e) {
      _mostrarSnack('Error al guardar: $e');
    }
  }

  void _mostrarSnack(String mensaje) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(mensaje)));
  }

  Future<void> _cerrarSesion() async {
    await Supabase.instance.client.auth.signOut();
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
  }

  void _cargarRegistroParaEditar(dynamic r) {
    setState(() {
      _idRegistroEditando = r['id']?.toString();
      _fechaSeleccionada = DateTime.parse(r['fecha']);
      _telarControllers[0].text = _metrosEnteros(r['t1_metros']);
      _telarControllers[1].text = _metrosEnteros(r['t2_metros']);
      _telarControllers[2].text = _metrosEnteros(r['t3_metros']);
      _telarControllers[3].text = _metrosEnteros(r['t4_metros']);
      _notasController.text = r['notas'] ?? '';
    });
    _mostrarSnack('Registro cargado para editar');
  }

  void _limpiarFormulario() {
    setState(() {
      _idRegistroEditando = null;
      _fechaSeleccionada = DateTime.now();
      for (var c in _telarControllers) {
        c.clear();
      }
      _notasController.clear();
    });
  }

  Future<DateTime?> _seleccionarFechaParaGuardar() {
    return showDatePicker(
      context: context,
      initialDate: _fechaSeleccionada,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
  }

  Future<void> _mostrarConfiguracionMeta() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('DIAS DE ASUETO O VACACIONES'),
          content: _buildCamposDiasLaborales(),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Listo'),
            ),
          ],
        );
      },
    );
  }

  List<Map<String, dynamic>> _rankingFiltrado() {
    if (_turnoFiltroRanking == 'Todos') return _rankingQuincena;
    return _rankingQuincena
        .where((item) => item['turno']?.toString() == _turnoFiltroRanking)
        .toList();
  }

  Widget _buildFiltroRanking(StateSetter setStateDialog) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: ['Todos', 'A', 'B', 'C'].map((turno) {
        final seleccionado = _turnoFiltroRanking == turno;
        final label = turno == 'Todos' ? '3 turnos' : 'Turno $turno';

        return ChoiceChip(
          label: Text(label),
          selected: seleccionado,
          selectedColor: const Color(0xFFDBDBF0),
          onSelected: (_) {
            setStateDialog(() => _turnoFiltroRanking = turno);
            setState(() => _turnoFiltroRanking = turno);
          },
        );
      }).toList(),
    );
  }

  Widget _buildSelectorPeriodoRanking(StateSetter setStateDialog) {
    final periodos = _periodosRankingDisponibles();

    return DropdownButtonFormField<String>(
      initialValue: _periodoFiltroRanking,
      decoration: const InputDecoration(
        labelText: 'Quincena',
        border: OutlineInputBorder(),
        prefixIcon: Icon(Icons.calendar_month),
      ),
      items: periodos
          .map(
            (periodo) => DropdownMenuItem<String>(
              value: periodo['clave'],
              child: Text(periodo['label'] ?? ''),
            ),
          )
          .toList(),
      onChanged: (valor) async {
        if (valor == null) return;
        setState(() => _periodoFiltroRanking = valor);
        setStateDialog(() {});
        await _cargarRankingQuincena();
        if (mounted) setStateDialog(() {});
      },
    );
  }

  Widget _buildItemRanking(Map<String, dynamic> item, int index) {
    final nombre = item['nombre']?.toString() ?? 'N/A';
    final turno = item['turno']?.toString() ?? '-';
    final total = item['total'] as double;
    final porcentaje = item['porcentajeRitmo'] as double;
    final progreso = (porcentaje / 100).clamp(0.0, 1.0);
    final colorPorcentaje = _colorPorcentaje(porcentaje);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE7E6F0)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 17,
            backgroundColor: const Color(0xFF1E2265),
            foregroundColor: Colors.white,
            child: Text(
              '${index + 1}',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        nombre,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Text(
                      '${_metrosEnteros(total)}m',
                      style: const TextStyle(
                        color: Color(0xFF1E2265),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 7),
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
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Text(
                      'Ritmo ${porcentaje.toStringAsFixed(1)}%',
                      style: TextStyle(
                        color: colorPorcentaje,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: progreso,
                    minHeight: 9,
                    backgroundColor: const Color(0xFFE8E8F4),
                    color: colorPorcentaje,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _mostrarRankingQuincena() async {
    if (_rankingQuincena.isEmpty && !_isLoadingRanking) {
      await _cargarRankingQuincena();
    }

    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFFFAFAFD),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            final ranking = _rankingFiltrado();

            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                child: SizedBox(
                  height: MediaQuery.of(context).size.height * 0.72,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 44,
                          height: 4,
                          decoration: BoxDecoration(
                            color: const Color(0xFFD6D3E3),
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: const Color(0xFFDBDBF0),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(
                              Icons.leaderboard,
                              color: Color(0xFF1E2265),
                            ),
                          ),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text(
                              'Ranking de quincena',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Actualizar',
                            onPressed: () async {
                              await _cargarRankingQuincena();
                              if (mounted) setStateDialog(() {});
                            },
                            icon: const Icon(
                              Icons.refresh,
                              color: Color(0xFF1E2265),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _buildSelectorPeriodoRanking(setStateDialog),
                      const SizedBox(height: 12),
                      _buildFiltroRanking(setStateDialog),
                      const SizedBox(height: 12),
                      Expanded(
                        child: _isLoadingRanking
                            ? const Center(
                                child: CircularProgressIndicator(
                                  color: Color(0xFF1E2265),
                                ),
                              )
                            : ranking.isEmpty
                            ? const Center(
                                child: Text(
                                  'Sin registros en la quincena actual.',
                                  style: TextStyle(color: Colors.black54),
                                ),
                              )
                            : ListView.separated(
                                itemCount: ranking.length,
                                separatorBuilder: (_, index) =>
                                    const SizedBox(height: 8),
                                itemBuilder: (context, index) =>
                                    _buildItemRanking(ranking[index], index),
                              ),
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

  Widget _buildCamposDiasLaborales() {
    if (_turnoLaboral == 'A' || _turnoLaboral == 'C') {
      return TextFormField(
        initialValue: _diasLVManuales?.toString() ?? '',
        decoration: const InputDecoration(
          labelText: 'Dias de asueto o vacaciones totales',
          border: OutlineInputBorder(),
        ),
        keyboardType: TextInputType.number,
        onChanged: (val) {
          setState(() {
            _diasLVManuales = int.tryParse(val);
            _diasSabadoManuales = 0;
            _calcularMetas();
          });
        },
      );
    } else {
      return Row(
        children: [
          Expanded(
            child: TextFormField(
              initialValue: _diasLVManuales?.toString() ?? '',
              decoration: const InputDecoration(
                labelText: 'L-V',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
              onChanged: (val) {
                setState(() {
                  _diasLVManuales = int.tryParse(val);
                  _calcularMetas();
                });
              },
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextFormField(
              initialValue: _diasSabadoManuales?.toString() ?? '',
              decoration: const InputDecoration(
                labelText: 'Sábado',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
              onChanged: (val) {
                setState(() {
                  _diasSabadoManuales = int.tryParse(val);
                  _calcularMetas();
                });
              },
            ),
          ),
        ],
      );
    }
  }

  Future<String?> _mostrarOpcionesRegistroExistente(String fecha) {
    return showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.warning_amber, color: Colors.orange),
                title: const Text('Ya existe un registro'),
                subtitle: Text('Ya tienes produccion guardada para $fecha'),
              ),
              ListTile(
                leading: const Icon(Icons.swap_horiz),
                title: const Text('Reemplazar'),
                subtitle: const Text('Sobrescribir el registro de esa fecha'),
                onTap: () => Navigator.pop(sheetContext, 'reemplazar'),
              ),
              ListTile(
                leading: const Icon(Icons.calendar_month),
                title: const Text('Editar fecha'),
                subtitle: const Text('Elegir otro dia para este registro'),
                onTap: () => Navigator.pop(sheetContext, 'editar_fecha'),
              ),
              ListTile(
                leading: const Icon(Icons.close),
                title: const Text('Cancelar'),
                onTap: () => Navigator.pop(sheetContext, 'cancelar'),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFF1E2265)),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: Text(
          'Hola, $_nombreOperador (Turno $_turnoLaboral)',
          style: const TextStyle(color: Colors.white, fontSize: 18),
        ),
        backgroundColor: const Color(0xFF1E2265),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            tooltip: 'Ranking de quincena',
            onPressed: _mostrarRankingQuincena,
            icon: const Icon(Icons.leaderboard),
          ),
          IconButton(
            tooltip: 'Historial de Quincenas',
            onPressed: () => Navigator.pushNamed(context, '/historial'),
            icon: const Icon(Icons.history),
          ),
          IconButton(
            tooltip: 'Configurar meta',
            onPressed: _mostrarConfiguracionMeta,
            icon: const Icon(Icons.settings),
          ),
          IconButton(
            tooltip: 'Cerrar sesion',
            onPressed: _cerrarSesion,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              elevation: 1,
              color: const Color(0xFFFAFAFD),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: const BorderSide(color: Color(0xFFE2E0E6)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: const Color(0xFFDBDBF0),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.flag,
                            color: Color(0xFF1E2265),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Tu Meta Es De: ${_metaQuincenaTotal.toStringAsFixed(0)}m',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    _buildBarraProgreso(
                      titulo: 'Progreso de quincena',
                      avance: _metrosTotalesQuincena,
                      meta: _metaQuincenaTotal,
                      color: const Color(0xFF1E2265),
                    ),
                    const SizedBox(height: 12),
                    _buildBarraProgreso(
                      titulo: 'Ritmo actual',
                      avance: _metrosTotalesQuincena,
                      meta: _metaRitmoActual,
                      color: Colors.green,
                    ),
                    const SizedBox(height: 12),
                    _buildCalculadoraMetaDeseada(),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _telarControllers[0],
                    decoration: _decoracionCampo('Primer Maquina', Icons.speed),//prueba de commit
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _telarControllers[1],
                    decoration: _decoracionCampo('Segunda Maquina', Icons.speed),
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
                    controller: _telarControllers[2],
                    decoration: _decoracionCampo('Tercera Maquina', Icons.speed),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _telarControllers[3],
                    decoration: _decoracionCampo('Cuarta Maquina', Icons.speed),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _notasController,
              decoration: _decoracionCampo(
                'Notas / Observaciones (opcional)',
                Icons.notes,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: _guardarRegistro,
                icon: const Icon(Icons.save),
                label: Text(
                  _idRegistroEditando == null
                      ? 'Guardar Producción del Día'
                      : 'Actualizar Registro',
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1E2265),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  elevation: 1,
                ),
              ),
            ),
            if (_idRegistroEditando != null)
              TextButton(
                onPressed: _limpiarFormulario,
                child: const Text(
                  'Cancelar Edición',
                  style: TextStyle(color: Colors.red),
                ),
              ),
            const Divider(height: 40),
            const Text(
              'Historial Activo (Toca para editar)',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            _historialQuincena.isEmpty
                ? const Text('Pantalla limpia. Inicia tus registros.')
                : ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _historialQuincena.length,
                    itemBuilder: (ctx, i) {
                      final h = _historialQuincena[i];
                      final total =
                          (h['t1_metros'] ?? 0) +
                          (h['t2_metros'] ?? 0) +
                          (h['t3_metros'] ?? 0) +
                          (h['t4_metros'] ?? 0);
                      final notas = (h['notas'] ?? '').toString().trim();
                      final estaEditando =
                          _idRegistroEditando == h['id']?.toString();

                      return Card(
                        elevation: 0,
                        color: estaEditando
                            ? Colors.yellow.shade100
                            : Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                          side: BorderSide(
                            color: estaEditando
                                ? Colors.amber.shade300
                                : const Color(0xFFE2E0E6),
                          ),
                        ),
                        child: ListTile(
                          onTap: () => _cargarRegistroParaEditar(h),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                          title: Text(
                            'Fecha: ${h['fecha']}',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'T1:${_metrosEnteros(h['t1_metros'])} T2:${_metrosEnteros(h['t2_metros'])} T3:${_metrosEnteros(h['t3_metros'])} T4:${_metrosEnteros(h['t4_metros'])}',
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
                                '${_metrosEnteros(total)}m',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  color: Color(0xFF1E2265),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Icon(
                                estaEditando ? Icons.edit_note : Icons.edit,
                                color: const Color(0xFF1E2265),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ],
        ),
      ),
    );
  }
}

//creo que ocn esto ya puedo hacer el commit, ya se que es un comentario tonto pero es para probar el commit de nuevo
