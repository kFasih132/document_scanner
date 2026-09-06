import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'core/theme/app_theme.dart';
import 'features/document_scanner/presentation/bloc/scanner_bloc.dart';
import 'features/document_scanner/presentation/screens/scanner_home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const DocScannerApp());
}

class DocScannerApp extends StatelessWidget {
  const DocScannerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider<ScannerBloc>(
      create: (context) => ScannerBloc(),
      child: MaterialApp(
        title: 'Doc Scanner M3',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: ThemeMode.system,
        home: const ScannerHomeScreen(),
      ),
    );
  }
}
