import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:trabalho_foly/turmas.dart';

typedef _DadosUsuario = ({bool admin, String? turma});

class Principal extends StatefulWidget {
  const Principal({super.key});

  @override
  State<Principal> createState() => _PrincipalState();
}

class _PrincipalState extends State<Principal> {
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;

  static const Color roxoPrincipal = Color(0xFF6A11CB);
  static const Color roxoSecundario = Color(0xFF8E2DE2);

  // Chaves do SharedPreferences
  static const String _kLogado = 'logado';
  static const String _kTurma = 'turma_salva';

  CollectionReference<Map<String, dynamic>> _eventosDe(String turma) =>
      FirebaseFirestore.instance
          .collection('turmas')
          .doc(turma)
          .collection('eventos');

  CollectionReference<Map<String, dynamic>> _pedidosDe(String turma) =>
      FirebaseFirestore.instance
          .collection('turmas')
          .doc(turma)
          .collection('pedidos');

  Future<_DadosUsuario>? _dadosFuture;
  String? _dadosUid;

  // Turma lembrada localmente (evita piscar a tela no F5)
  String? _turmaEscolhida;

  // Streams guardados para não serem recriados a cada setState (evita piscar)
  final Stream<User?> _authStream = FirebaseAuth.instance.authStateChanges();

  Stream<DocumentSnapshot<Map<String, dynamic>>>? _userDocStream;
  String? _userDocUid;

  Stream<DocumentSnapshot<Map<String, dynamic>>>? _userDocStreamPara(
      User? user) {
    if (user == null) {
      _userDocStream = null;
      _userDocUid = null;
      return null;
    }
    if (_userDocUid != user.uid) {
      _userDocUid = user.uid;
      _userDocStream = FirebaseFirestore.instance
          .collection('usuarios')
          .doc(user.uid)
          .snapshots();
    }
    return _userDocStream;
  }

  Stream<QuerySnapshot>? _eventosStream;
  String? _eventosChave;

  Stream<QuerySnapshot> _eventosStreamPara(String turma) {
    final chave = '$turma-${_focusedDay.year}-${_focusedDay.month}';
    if (_eventosChave != chave) {
      _eventosChave = chave;
      _eventosStream = _eventosDe(turma)
          .where('data',
              isGreaterThanOrEqualTo: Timestamp.fromDate(
                  DateTime(_focusedDay.year, _focusedDay.month, 1)))
          .where('data',
              isLessThan: Timestamp.fromDate(
                  DateTime(_focusedDay.year, _focusedDay.month + 1, 1)))
          .snapshots();
    }
    return _eventosStream!;
  }

  SharedPreferences? _prefs;
  bool _prefsCarregadas = false;
  StreamSubscription<User?>? _authSub;

  @override
  void initState() {
    super.initState();
    _iniciarPrefs();
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  Future<void> _iniciarPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    _prefs = prefs;

    // Restaura a turma salva
    final turmaSalva = prefs.getString(_kTurma);
    if (turmaSalva != null && listaTurmas.contains(turmaSalva)) {
      _turmaEscolhida = turmaSalva;
    }

    // Mantém o SharedPreferences sincronizado com o estado real do login
    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) async {
      if (user != null) {
        await prefs.setBool(_kLogado, true);
      } else {
        await prefs.setBool(_kLogado, false);
        await prefs.remove(_kTurma);
      }
    });

    if (!mounted) return;
    setState(() => _prefsCarregadas = true);
  }

  Future<void> _salvarTurmaLocal(String turma) async {
    await _prefs?.setString(_kTurma, turma);
  }

  DateTime _apenasData(DateTime d) {
    return DateTime(d.year, d.month, d.day);
  }

  void _mostrarMensagem(String mensagem) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(mensagem)),
    );
  }

  Future<bool> _enviarPedido(String texto, String turma) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || texto.trim().isEmpty) return false;

    try {
      await _pedidosDe(turma).add({
        'descricao': texto.trim(),
        'turma': turma,
        'uid': user.uid,
        'email': user.email?.toLowerCase(),
        'nome': user.displayName,
        'criadoEm': FieldValue.serverTimestamp(),
      });
      _mostrarMensagem('Pedido enviado ao administrador!');
      return true;
    } catch (e) {
      debugPrint('Erro ao enviar pedido: $e');
      _mostrarMensagem('Erro ao enviar pedido: $e');
      return false;
    }
  }

  void _abrirDialogoPedido(String turma) {
    final controller = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: const Text(
          'Pedido ao administrador',
          style: TextStyle(fontWeight: FontWeight.bold, color: roxoPrincipal),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 4,
          decoration: InputDecoration(
            hintText: 'Ex.: adicionar prova de matemática dia 20/10',
            filled: true,
            fillColor: const Color(0xFFF5F3FB),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: roxoPrincipal, width: 1.5),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: roxoPrincipal,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              final ok = await _enviarPedido(controller.text, turma);
              if (ok && dialogContext.mounted) Navigator.pop(dialogContext);
            },
            child: const Text('Enviar'),
          ),
        ],
      ),
    ).then((_) => controller.dispose());
  }

  void _abrirMeusPedidos(String turma) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        builder: (context, scroll) => StreamBuilder<QuerySnapshot>(
          stream: _pedidosDe(turma).where('uid', isEqualTo: uid).snapshots(),
          builder: (context, snap) {
            if (snap.hasError) {
              return Center(child: Text('Erro: ${snap.error}'));
            }
            if (!snap.hasData) {
              return const Center(
                child: CircularProgressIndicator(color: roxoPrincipal),
              );
            }
            final docs = snap.data!.docs;
            if (docs.isEmpty) {
              return const Center(
                child: Text('Você ainda não enviou pedidos'),
              );
            }
            return ListView.separated(
              controller: scroll,
              padding: const EdgeInsets.all(16),
              itemCount: docs.length,
              separatorBuilder: (_, _) => const Divider(),
              itemBuilder: (context, i) {
                final d = docs[i].data() as Map<String, dynamic>;
                return ListTile(
                  leading:
                      const Icon(Icons.send_outlined, color: roxoPrincipal),
                  title: Text(d['descricao'] ?? ''),
                );
              },
            );
          },
        ),
      ),
    );
  }

  void _abrirPedidos(String turma) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        builder: (context, scroll) => StreamBuilder<QuerySnapshot>(
          stream: _pedidosDe(turma).snapshots(),
          builder: (context, snap) {
            if (snap.hasError) {
              return Center(child: Text('Erro: ${snap.error}'));
            }
            if (!snap.hasData) {
              return const Center(
                child: CircularProgressIndicator(color: roxoPrincipal),
              );
            }
            final docs = snap.data!.docs;
            if (docs.isEmpty) {
              return const Center(child: Text('Nenhum pedido'));
            }
            return ListView.separated(
              controller: scroll,
              padding: const EdgeInsets.all(16),
              itemCount: docs.length,
              separatorBuilder: (_, _) => const Divider(),
              itemBuilder: (context, i) {
                final d = docs[i].data() as Map<String, dynamic>;
                final autor = (d['nome'] as String?)?.isNotEmpty == true
                    ? d['nome']
                    : d['email'] ?? '';
                return ListTile(
                  title: Text(d['descricao'] ?? ''),
                  subtitle: Text('$autor'),
                  trailing: IconButton(
                    icon: const Icon(Icons.check_circle_outline,
                        color: roxoPrincipal),
                    tooltip: 'Concluir (remover)',
                    onPressed: () => _pedidosDe(turma).doc(docs[i].id).delete(),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  // Só verifica se o usuário é administrador.
  // A turma vem do stream do documento do usuário (ver build).
  Future<_DadosUsuario> _carregarDados(User? user) async {
    if (user == null) {
      return (admin: false, turma: null);
    }

    bool admin = false;

    try {
      final adminDoc = await FirebaseFirestore.instance
          .collection('administradores')
          .doc(user.uid)
          .get();
      admin = adminDoc.exists;
    } catch (e) {
      debugPrint('Erro ao verificar administrador: $e');
    }

    return (admin: admin, turma: null);
  }

  Future<_DadosUsuario> _dadosPara(User? user) {
    final uid = user?.uid;

    if (_dadosFuture == null || _dadosUid != uid) {
      _dadosUid = uid;
      _dadosFuture = _carregarDados(user);
    }

    return _dadosFuture!;
  }

  Future<bool> _adicionarEvento(String texto, String turma) async {
    if (_selectedDay == null || texto.trim().isEmpty) {
      return false;
    }

    try {
      await _eventosDe(turma).add({
        'data': Timestamp.fromDate(
          _apenasData(_selectedDay!),
        ),
        'descricao': texto.trim(),
        'turma': turma,
        'criadoEm': FieldValue.serverTimestamp(),
      });
      return true;
    } catch (e) {
      debugPrint('Erro ao adicionar: $e');
      _mostrarMensagem('Erro ao adicionar: $e');
      return false;
    }
  }

  Future<void> _removerEvento(String turma, String docId) async {
    try {
      await _eventosDe(turma).doc(docId).delete();
    } catch (e) {
      debugPrint('Erro ao remover: $e');
      _mostrarMensagem('Erro ao remover: $e');
    }
  }

  void _abrirDialogoAdicionarEvento(String turma) {
    final controller = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: Text(
          'Novo evento – $turma',
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: roxoPrincipal,
          ),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            hintText: 'Descrição do evento',
            filled: true,
            fillColor: const Color(0xFFF5F3FB),
            isDense: true,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14.0),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14.0),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14.0),
              borderSide: const BorderSide(
                color: roxoPrincipal,
                width: 1.5,
              ),
            ),
            contentPadding: const EdgeInsets.symmetric(
              vertical: 14,
              horizontal: 14,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
            },
            style: TextButton.styleFrom(
              foregroundColor: Colors.grey[600],
            ),
            child: const Text('Cancelar'),
          ),
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14.0),
              gradient: const LinearGradient(
                colors: [
                  roxoPrincipal,
                  roxoSecundario,
                ],
              ),
            ),
            child: ElevatedButton(
              onPressed: () async {
                final ok = await _adicionarEvento(controller.text, turma);

                if (ok && dialogContext.mounted) {
                  Navigator.pop(dialogContext);
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14.0),
                ),
              ),
              child: const Text(
                'Adicionar',
                style: TextStyle(
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    ).then((_) => controller.dispose());
  }

  Future<void> _sair() async {
    await FirebaseAuth.instance.signOut();

    await _prefs?.setBool(_kLogado, false);
    await _prefs?.remove(_kTurma);

    _dadosFuture = null;
    _dadosUid = null;
    _turmaEscolhida = null;
    _userDocStream = null;
    _userDocUid = null;
    _eventosStream = null;
    _eventosChave = null;
    // Sem Navigator: o AuthGate volta para o Login sozinho.
  }

  Widget _faixaTurma(String turma) {
    return Container(
      margin: const EdgeInsets.fromLTRB(32, 16, 32, 0),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const Icon(Icons.groups_outlined, color: roxoPrincipal),
          const SizedBox(width: 10),
          Text(
            'Turma: $turma',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: roxoPrincipal,
            ),
          ),
        ],
      ),
    );
  }

  Widget _telaCarregando() {
    return const Scaffold(
      backgroundColor: Color(0xFFF5F3FB),
      body: Center(
        child: CircularProgressIndicator(color: roxoPrincipal),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Espera o SharedPreferences carregar
    if (!_prefsCarregadas) return _telaCarregando();

    return StreamBuilder<User?>(
      stream: _authStream,
      builder: (context, authSnapshot) {
        // Espera o Firebase restaurar a sessão (evita "piscar" deslogado no F5)
        if (authSnapshot.connectionState == ConnectionState.waiting) {
          return _telaCarregando();
        }

        final user = authSnapshot.data;
        final logado = user != null;

        final nomeUsuario = user?.displayName?.isNotEmpty == true
            ? user!.displayName!
            : user?.email ?? '';

        return FutureBuilder<_DadosUsuario>(
          future: _dadosPara(user),
          builder: (context, dadosSnapshot) {
            final ehAdmin = dadosSnapshot.data?.admin ?? false;

            return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: _userDocStreamPara(user),
              builder: (context, userSnap) {
                final t = userSnap.data?.data()?['turma'];
                final String? turmaDoUsuario =
                    (t is String && listaTurmas.contains(t)) ? t : null;

                // Guarda localmente para o próximo F5
                if (turmaDoUsuario != null &&
                    turmaDoUsuario != _turmaEscolhida) {
                  _turmaEscolhida = turmaDoUsuario;
                  _salvarTurmaLocal(turmaDoUsuario);
                }

                final String? turmaVisivel =
                    turmaDoUsuario ?? _turmaEscolhida;

                final carregando =
                    dadosSnapshot.connectionState ==
                            ConnectionState.waiting ||
                        userSnap.connectionState == ConnectionState.waiting;

                return Scaffold(
                  backgroundColor: const Color(0xFFF5F3FB),
                  extendBodyBehindAppBar: false,
                  appBar: AppBar(
                    elevation: 0,
                    automaticallyImplyLeading: false,
                    flexibleSpace: Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            roxoPrincipal,
                            roxoSecundario,
                          ],
                        ),
                      ),
                    ),
                    title: const Text(
                      'Calendário',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    actions: [
                      if (logado) ...[
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                          ),
                          child: Center(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.18),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                nomeUsuario,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.logout,
                            color: Colors.white,
                          ),
                          tooltip: 'Sair',
                          onPressed: _sair,
                        ),
                        const SizedBox(width: 4),
                      ],
                    ],
                  ),
                  body: turmaVisivel != null
                      ? _corpo(ehAdmin, turmaVisivel)
                      : carregando
                          ? const Center(
                              child: CircularProgressIndicator(
                                color: roxoPrincipal,
                              ),
                            )
                          : const Center(
                              child: Text(
                                'Não foi possível encontrar sua turma.',
                              ),
                            ),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _corpo(bool ehAdmin, String turma) {
    final logado = FirebaseAuth.instance.currentUser != null;

    return StreamBuilder<QuerySnapshot>(
      stream: _eventosStreamPara(turma),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Text(
              'Erro ao carregar eventos: ${snapshot.error}',
            ),
          );
        }

        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const Center(
            child: CircularProgressIndicator(
              color: roxoPrincipal,
            ),
          );
        }

        final docs = snapshot.data?.docs ?? [];

        final Map<DateTime, List<QueryDocumentSnapshot>> agrupado = {};

        for (final doc in docs) {
          final ts = (doc['data'] as Timestamp).toDate();
          final chave = _apenasData(ts);

          agrupado.putIfAbsent(chave, () => []).add(doc);
        }

        List<QueryDocumentSnapshot> eventosDoDia(DateTime dia) {
          return agrupado[_apenasData(dia)] ?? [];
        }

        final List<QueryDocumentSnapshot> eventosSelecionados =
            _selectedDay != null ? eventosDoDia(_selectedDay!) : [];

        return SingleChildScrollView(
          child: Column(
            children: [
              _faixaTurma(turma),
              Container(
                margin: const EdgeInsets.fromLTRB(64, 24, 64, 16),
                padding: const EdgeInsets.symmetric(
                  vertical: 32,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: TableCalendar(
                  locale: 'pt_BR',
                  firstDay: DateTime.utc(2026, 1, 1),
                  lastDay: DateTime.utc(2030, 12, 31),
                  focusedDay: _focusedDay,
                  selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
                  eventLoader: eventosDoDia,
                  onDaySelected: (selectedDay, focusedDay) {
                    setState(() {
                      _selectedDay = selectedDay;
                      _focusedDay = focusedDay;
                    });
                  },
                  onPageChanged: (focusedDay) {
                    setState(() {
                      _focusedDay = focusedDay;
                      _selectedDay = null;
                    });
                  },
                  headerStyle: const HeaderStyle(
                    formatButtonVisible: false,
                    titleCentered: true,
                    titleTextStyle: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: roxoPrincipal,
                    ),
                    leftChevronIcon: Icon(
                      Icons.chevron_left,
                      color: roxoPrincipal,
                    ),
                    rightChevronIcon: Icon(
                      Icons.chevron_right,
                      color: roxoPrincipal,
                    ),
                  ),
                  daysOfWeekStyle: DaysOfWeekStyle(
                    weekdayStyle: TextStyle(
                      color: Colors.grey[600],
                      fontWeight: FontWeight.w600,
                    ),
                    weekendStyle: TextStyle(
                      color: Colors.grey[600],
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  calendarStyle: CalendarStyle(
                    outsideDaysVisible: false,
                    todayDecoration: BoxDecoration(
                      color: roxoSecundario.withValues(alpha: 0.3),
                      shape: BoxShape.circle,
                    ),
                    selectedDecoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          roxoPrincipal,
                          roxoSecundario,
                        ],
                      ),
                      shape: BoxShape.circle,
                    ),
                    markerDecoration: const BoxDecoration(
                      color: roxoPrincipal,
                      shape: BoxShape.circle,
                    ),
                    markersMaxCount: 3,
                  ),
                ),
              ),
              if (ehAdmin)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                  ),
                  child: SizedBox(
                    width: 1000,
                    height: 52,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(15.0),
                        gradient: LinearGradient(
                          colors: _selectedDay == null
                              ? [
                                  Colors.grey[300]!,
                                  Colors.grey[300]!,
                                ]
                              : const [
                                  roxoPrincipal,
                                  roxoSecundario,
                                ],
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                        ),
                      ),
                      child: ElevatedButton.icon(
                        onPressed: _selectedDay == null
                            ? null
                            : () => _abrirDialogoAdicionarEvento(turma),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          disabledBackgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(15.0),
                          ),
                        ),
                        icon: const Icon(
                          Icons.add,
                          color: Colors.white,
                        ),
                        label: const Text(
                          'Adicionar evento',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              if (!ehAdmin && logado) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: SizedBox(
                    width: 1000,
                    height: 52,
                    child: OutlinedButton.icon(
                      onPressed: () => _abrirDialogoPedido(turma),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: roxoPrincipal,
                        side: const BorderSide(color: roxoPrincipal),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15),
                        ),
                      ),
                      icon: const Icon(Icons.send_outlined),
                      label: const Text(
                        'Enviar pedido ao administrador',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: SizedBox(
                    width: 1000,
                    height: 52,
                    child: OutlinedButton.icon(
                      onPressed: () => _abrirMeusPedidos(turma),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: roxoPrincipal,
                        side: const BorderSide(color: roxoPrincipal),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15),
                        ),
                      ),
                      icon: const Icon(Icons.list_alt_outlined),
                      label: const Text(
                        'Meus pedidos',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ),
              ],
              if (ehAdmin)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: SizedBox(
                    width: 1000,
                    height: 52,
                    child: OutlinedButton.icon(
                      onPressed: () => _abrirPedidos(turma),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: roxoPrincipal,
                        side: const BorderSide(color: roxoPrincipal),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15),
                        ),
                      ),
                      icon: const Icon(Icons.inbox_outlined),
                      label: const Text(
                        'Ver pedidos',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                ),
                child: eventosSelecionados.isEmpty
                    ? Container(
                        width: 1000,
                        padding: const EdgeInsets.symmetric(
                          vertical: 32,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Column(
                          children: [
                            Icon(
                              Icons.event_busy,
                              size: 40,
                              color: Colors.grey[400],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _selectedDay == null
                                  ? 'Selecione um dia'
                                  : 'Nenhum evento neste dia',
                              style: TextStyle(
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: eventosSelecionados.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final doc = eventosSelecionados[index];
                          final descricao = doc['descricao'] as String;

                          return Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.05),
                                  blurRadius: 8,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: ListTile(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              leading: Container(
                                width: 42,
                                height: 42,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: roxoPrincipal.withValues(alpha: 0.1),
                                ),
                                child: const Icon(
                                  Icons.event,
                                  color: roxoPrincipal,
                                ),
                              ),
                              title: Text(
                                descricao,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              trailing: ehAdmin
                                  ? IconButton(
                                      icon: const Icon(
                                        Icons.delete_outline,
                                        color: Colors.redAccent,
                                      ),
                                      tooltip: 'Excluir',
                                      onPressed: () =>
                                          _removerEvento(turma, doc.id),
                                    )
                                  : null,
                            ),
                          );
                        },
                      ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        );
      },
    );
  }
}