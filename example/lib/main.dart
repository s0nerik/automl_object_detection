import 'package:flutter/material.dart';

import 'analysis_screen.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatefulWidget {
  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          appBar: AppBar(),
          body: Center(
            child: RaisedButton(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (context) => AnalysisScreen(),
              )),
              child: Text('Analysis'),
            ),
          ),
        ),
      ),
    );
  }
}
