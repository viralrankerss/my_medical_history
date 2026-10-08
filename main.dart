import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MedicalApp());
}

String dateText(DateTime date) =>
    '${date.day.toString().padLeft(2, '0')}/'
    '${date.month.toString().padLeft(2, '0')}/${date.year}';

String normalizeDoctor(String name) =>
    name.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

class MedicalVisit {
  final int? id;
  final String doctor;
  final String hospital;
  final String diagnosis;
  final String medicine;
  final DateTime date;

  const MedicalVisit({
    this.id,
    required this.doctor,
    required this.hospital,
    required this.diagnosis,
    required this.medicine,
    required this.date,
  });

  Map<String, Object?> toMap() => {
        'doctor': doctor,
        'hospital': hospital,
        'diagnosis': diagnosis,
        'medicine': medicine,
        'date': date.toIso8601String(),
      };

  factory MedicalVisit.fromMap(Map<String, Object?> map) => MedicalVisit(
        id: map['id'] as int,
        doctor: map['doctor'] as String,
        hospital: map['hospital'] as String,
        diagnosis: map['diagnosis'] as String,
        medicine: map['medicine'] as String,
        date: DateTime.parse(map['date'] as String),
      );
}

class MedicalDatabase {
  MedicalDatabase._();
  static final MedicalDatabase instance = MedicalDatabase._();
  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    final directory = await getDatabasesPath();
    _db = await openDatabase(
      p.join(directory, 'medical_history.db'),
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE visits (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            doctor TEXT NOT NULL,
            hospital TEXT NOT NULL,
            diagnosis TEXT NOT NULL,
            medicine TEXT NOT NULL,
            date TEXT NOT NULL
          )
        ''');
      },
    );
    return _db!;
  }

  Future<List<MedicalVisit>> getVisits() async {
    final db = await database;
    final rows = await db.query('visits', orderBy: 'date DESC, id DESC');
    return rows.map(MedicalVisit.fromMap).toList();
  }

  Future<void> saveVisit(MedicalVisit visit) async {
    final db = await database;
    if (visit.id == null) {
      await db.insert('visits', visit.toMap());
    } else {
      await db.update(
        'visits',
        visit.toMap(),
        where: 'id = ?',
        whereArgs: [visit.id],
      );
    }
  }

  Future<void> deleteVisit(int id) async {
    final db = await database;
    await db.delete('visits', where: 'id = ?', whereArgs: [id]);
  }
}

class MedicalApp extends StatelessWidget {
  const MedicalApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'My Medical History',
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1976D2)),
          scaffoldBackgroundColor: const Color(0xFFF5F8FC),
          inputDecorationTheme: InputDecorationTheme(
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            filled: true,
            fillColor: Colors.white,
          ),
        ),
        home: const HomeScreen(),
      );
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<MedicalVisit> visits = [];
  bool loading = true;
  String? error;
  int selectedTab = 0;
  String search = '';
  final searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    refresh();
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  Future<void> refresh() async {
    try {
      final data = await MedicalDatabase.instance.getVisits();
      if (!mounted) return;
      setState(() {
        visits = data;
        loading = false;
        error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        loading = false;
        error = '$e';
      });
    }
  }

  void notify(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> addOrEdit({MedicalVisit? existing, String? doctor, String? hospital}) async {
    final result = await Navigator.push<MedicalVisit>(
      context,
      MaterialPageRoute(
        builder: (_) => VisitFormScreen(
          existing: existing,
          initialDoctor: doctor,
          initialHospital: hospital,
        ),
      ),
    );
    if (result == null || !mounted) return;
    try {
      await MedicalDatabase.instance.saveVisit(result);
      await refresh();
      notify(existing == null ? 'Visit saved on this phone' : 'Visit updated');
    } catch (e) {
      notify('Could not save visit: $e');
    }
  }

  Future<void> openVisit(MedicalVisit visit) async {
    final action = await Navigator.push<VisitAction>(
      context,
      MaterialPageRoute(builder: (_) => VisitDetailScreen(visit: visit)),
    );
    if (!mounted) return;
    if (action == VisitAction.edit) {
      await addOrEdit(existing: visit);
    } else if (action == VisitAction.delete) {
      try {
        await MedicalDatabase.instance.deleteVisit(visit.id!);
        await refresh();
        notify('Visit deleted');
      } catch (e) {
        notify('Could not delete visit: $e');
      }
    }
  }

  List<MedicalVisit> visitsByDoctor(String key) =>
      visits.where((v) => normalizeDoctor(v.doctor) == key).toList();

  Future<void> openDoctor(String key) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => DoctorScreen(
          doctorKey: key,
          getVisits: () => visitsByDoctor(key),
          onOpenVisit: openVisit,
          onAddVisit: (doctor, hospital) =>
              addOrEdit(doctor: doctor, hospital: hospital),
        ),
      ),
    );
    if (mounted) await refresh();
  }

  @override
  Widget build(BuildContext context) {
    final doctorKeys = visits.map((v) => normalizeDoctor(v.doctor)).toSet().toList()..sort();
    final query = search.trim().toLowerCase();
    final filteredVisits = visits.where((v) => v.doctor.toLowerCase().contains(query)).toList();
    final filteredDoctors = doctorKeys.where((key) => key.contains(query)).toList();
    const names = ['Recent Visits', 'My Doctors', 'Medical History'];

    return Scaffold(
      appBar: AppBar(title: const Text('My Medical History')),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Database error: $error', textAlign: TextAlign.center),
                      TextButton(onPressed: refresh, child: const Text('Retry')),
                    ],
                  ),
                )
              : Column(
                  children: [
                    if (selectedTab == 0)
                      Card(
                        margin: const EdgeInsets.all(16),
                        color: const Color(0xFF1976D2),
                        child: Padding(
                          padding: const EdgeInsets.all(22),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const Icon(Icons.health_and_safety, color: Colors.white, size: 40),
                              const SizedBox(height: 8),
                              const Text('Your Health Records',
                                  style: TextStyle(color: Colors.white, fontSize: 21, fontWeight: FontWeight.bold)),
                              Text('${visits.length} visits • ${doctorKeys.length} doctors',
                                  style: const TextStyle(color: Colors.white)),
                              const Text('Saved offline on your phone',
                                  style: TextStyle(color: Colors.white70)),
                            ],
                          ),
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: TextField(
                        controller: searchController,
                        onChanged: (text) => setState(() => search = text),
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.search),
                          hintText: 'Search by doctor name',
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(names[selectedTab],
                            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: selectedTab == 1
                          ? filteredDoctors.isEmpty
                              ? const Center(child: Text('No doctors found. Add a visit first.'))
                              : ListView.builder(
                                  itemCount: filteredDoctors.length,
                                  itemBuilder: (context, i) {
                                    final key = filteredDoctors[i];
                                    final history = visitsByDoctor(key);
                                    return Card(
                                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
                                      child: ListTile(
                                        leading: const CircleAvatar(child: Icon(Icons.person)),
                                        title: Text(history.first.doctor),
                                        subtitle: Text('${history.first.hospital} • ${history.length} visits'),
                                        trailing: const Icon(Icons.chevron_right),
                                        onTap: () => openDoctor(key),
                                      ),
                                    );
                                  },
                                )
                          : filteredVisits.isEmpty
                              ? const Center(child: Text('No visits found. Tap Add Visit.'))
                              : ListView.builder(
                                  itemCount: filteredVisits.length,
                                  itemBuilder: (context, i) {
                                    final visit = filteredVisits[i];
                                    return Card(
                                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
                                      child: ListTile(
                                        leading: const CircleAvatar(child: Icon(Icons.medical_services)),
                                        title: Text(visit.doctor),
                                        subtitle: Text('${visit.hospital}\n${visit.diagnosis} • ${dateText(visit.date)}'),
                                        isThreeLine: true,
                                        trailing: const Icon(Icons.chevron_right),
                                        onTap: () => openVisit(visit),
                                      ),
                                    );
                                  },
                                ),
                    ),
                  ],
                ),
      floatingActionButton: loading || error != null
          ? null
          : FloatingActionButton.extended(
              onPressed: () => addOrEdit(),
              icon: const Icon(Icons.add),
              label: const Text('Add Visit'),
            ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedTab,
        onDestinationSelected: (index) {
          setState(() {
            selectedTab = index;
            search = '';
            searchController.clear();
          });
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.people_outline), label: 'Doctors'),
          NavigationDestination(icon: Icon(Icons.history), label: 'History'),
        ],
      ),
    );
  }
}

class DoctorScreen extends StatefulWidget {
  final String doctorKey;
  final List<MedicalVisit> Function() getVisits;
  final Future<void> Function(MedicalVisit) onOpenVisit;
  final Future<void> Function(String, String) onAddVisit;

  const DoctorScreen({
    super.key,
    required this.doctorKey,
    required this.getVisits,
    required this.onOpenVisit,
    required this.onAddVisit,
  });

  @override
  State<DoctorScreen> createState() => _DoctorScreenState();
}

class _DoctorScreenState extends State<DoctorScreen> {
  @override
  Widget build(BuildContext context) {
    final history = widget.getVisits();
    if (history.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Doctor Profile')),
        body: const Center(child: Text('No visits under this doctor.')),
      );
    }
    final doctor = history.first;
    return Scaffold(
      appBar: AppBar(title: const Text('Doctor Profile')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  const CircleAvatar(radius: 34, child: Icon(Icons.person, size: 38)),
                  const SizedBox(height: 12),
                  Text(doctor.doctor,
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                  Text(doctor.hospital),
                  Chip(label: Text('${history.length} Total Visits')),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            icon: const Icon(Icons.add),
            label: const Text('Add Visit for This Doctor'),
            onPressed: () async {
              await widget.onAddVisit(doctor.doctor, doctor.hospital);
              if (mounted) setState(() {});
            },
          ),
          const SizedBox(height: 18),
          const Text('Visit History',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          ...history.map((visit) => Card(
                child: ListTile(
                  leading: const Icon(Icons.calendar_month),
                  title: Text(dateText(visit.date)),
                  subtitle: Text('${visit.diagnosis}\n${visit.medicine}'),
                  isThreeLine: true,
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    await widget.onOpenVisit(visit);
                    if (mounted) setState(() {});
                  },
                ),
              )),
        ],
      ),
    );
  }
}

class VisitFormScreen extends StatefulWidget {
  final MedicalVisit? existing;
  final String? initialDoctor;
  final String? initialHospital;

  const VisitFormScreen({super.key, this.existing, this.initialDoctor, this.initialHospital});

  @override
  State<VisitFormScreen> createState() => _VisitFormScreenState();
}

class _VisitFormScreenState extends State<VisitFormScreen> {
  final formKey = GlobalKey<FormState>();
  final doctor = TextEditingController();
  final hospital = TextEditingController();
  final diagnosis = TextEditingController();
  final medicine = TextEditingController();
  late DateTime selectedDate;

  @override
  void initState() {
    super.initState();
    doctor.text = widget.existing?.doctor ?? widget.initialDoctor ?? '';
    hospital.text = widget.existing?.hospital ?? widget.initialHospital ?? '';
    diagnosis.text = widget.existing?.diagnosis ?? '';
    medicine.text = widget.existing?.medicine ?? '';
    selectedDate = widget.existing?.date ?? DateTime.now();
  }

  @override
  void dispose() {
    doctor.dispose();
    hospital.dispose();
    diagnosis.dispose();
    medicine.dispose();
    super.dispose();
  }

  Widget field(String title, TextEditingController controller, IconData icon) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: TextFormField(
          controller: controller,
          decoration: InputDecoration(labelText: title, prefixIcon: Icon(icon)),
          validator: (text) => text == null || text.trim().isEmpty ? 'Please enter $title' : null,
        ),
      );

  void save() {
    if (!formKey.currentState!.validate()) return;
    Navigator.pop(
      context,
      MedicalVisit(
        id: widget.existing?.id,
        doctor: doctor.text.trim(),
        hospital: hospital.text.trim(),
        diagnosis: diagnosis.text.trim(),
        medicine: medicine.text.trim(),
        date: selectedDate,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(widget.existing == null ? 'Add Visit' : 'Edit Visit')),
        body: Form(
          key: formKey,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const Icon(Icons.medical_services, size: 54, color: Color(0xFF1976D2)),
              const SizedBox(height: 20),
              field('Doctor Name', doctor, Icons.person),
              field('Hospital Name', hospital, Icons.local_hospital),
              field('Diagnosis', diagnosis, Icons.health_and_safety),
              field('Medicine', medicine, Icons.medication),
              Card(
                child: ListTile(
                  title: const Text('Visit Date'),
                  subtitle: Text(dateText(selectedDate)),
                  leading: const Icon(Icons.calendar_today),
                  trailing: const Icon(Icons.edit_calendar),
                  onTap: () async {
                    final date = await showDatePicker(
                      context: context,
                      initialDate: selectedDate,
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                    );
                    if (date != null) setState(() => selectedDate = date);
                  },
                ),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: save,
                icon: const Icon(Icons.save),
                label: Text(widget.existing == null ? 'Save Visit' : 'Save Changes'),
              ),
            ],
          ),
        ),
      );
}

enum VisitAction { edit, delete }

class VisitDetailScreen extends StatelessWidget {
  final MedicalVisit visit;
  const VisitDetailScreen({super.key, required this.visit});

  Future<void> confirmDelete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Delete Medical Visit?'),
        content: const Text('This visit will be permanently removed from this phone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      Navigator.pop(context, VisitAction.delete);
    }
  }

  Widget info(String title, String value, IconData icon) => Card(
        child: ListTile(
          leading: Icon(icon, color: const Color(0xFF1976D2)),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
          subtitle: Text(value),
        ),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Visit Details'),
          actions: [
            IconButton(
              tooltip: 'Delete Visit',
              icon: const Icon(Icons.delete_outline, color: Colors.red),
              onPressed: () => confirmDelete(context),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const CircleAvatar(radius: 34, child: Icon(Icons.person, size: 38)),
            const SizedBox(height: 20),
            info('Doctor', visit.doctor, Icons.person),
            info('Hospital', visit.hospital, Icons.local_hospital),
            info('Diagnosis', visit.diagnosis, Icons.health_and_safety),
            info('Medicine', visit.medicine, Icons.medication),
            info('Visit Date', dateText(visit.date), Icons.calendar_today),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => Navigator.pop(context, VisitAction.edit),
              icon: const Icon(Icons.edit),
              label: const Text('Edit Medical Visit'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => confirmDelete(context),
              icon: const Icon(Icons.delete_outline),
              label: const Text('Delete Medical Visit'),
            ),
          ],
        ),
      );
}
