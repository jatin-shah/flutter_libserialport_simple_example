import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_libserialport/flutter_libserialport.dart';
import 'package:cp949/cp949.dart' as cp949;

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Tombot Robot Controller',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const MyHomePage(title: 'Tombot Robot Controller'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({Key? key, required this.title}) : super(key: key);
  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  List<SerialPort> portList = [];
  SerialPort? _serialPort;
  List<Uint8List> receiveDataList = [];
  final textInputCtrl = TextEditingController();
  final ScrollController logWindowController = ScrollController();
  bool _scrollEnable = false;

  @override
  void initState() {
    super.initState();
    var i = 0;
    for (final name in SerialPort.availablePorts) {
      final sp = SerialPort(name);
      if (kDebugMode) {
        print('${++i}) $name');
        print('\tDescription: ${cp949.decodeString(sp.description ?? '')}');
        print('\tManufacturer: ${sp.manufacturer}');
        print('\tSerial Number: ${sp.serialNumber}');
        print('\tProduct ID: 0x${sp.productId?.toRadixString(16) ?? 00}');
        print('\tVendor ID: 0x${sp.vendorId?.toRadixString(16) ?? 00}');
      }
      portList.add(sp);
    }
    if (portList.isNotEmpty) {
      _serialPort = portList.first;
    }
  }

  void changedDropDownItem(SerialPort sp) {
    setState(() {
      _serialPort = sp;
    });
  }

  @override
  Widget build(BuildContext context) {
    var openButtonText = _serialPort == null
        ? 'N/A'
        : _serialPort!.isOpen
            ? 'Close'
            : 'Open';
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
      ),
      body: SizedBox(
        height: double.infinity,
        child: Column(
          children: <Widget>[
            Expanded(
              flex: 1,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  DropdownButton(
                    value: _serialPort,
                    items: portList.map((item) {
                      return DropdownMenuItem(
                          child: Text(
                              "${item.name}: ${cp949.decodeString(item.description ?? '')}"),
                          value: item);
                    }).toList(),
                    onChanged: (e) {
                      setState(() {
                        changedDropDownItem(e as SerialPort);
                      });
                    },
                  ),
                  const SizedBox(
                    width: 50.0,
                  ),
                  OutlinedButton(
                    child: Text(openButtonText),
                    onPressed: setupSerialPort,
                  ),
                  const SizedBox(
                    width: 50.0,
                  ),
                  const Text('Enable Scrolling: '),
                  Checkbox(value: _scrollEnable, onChanged: changeScrollSetting),
                  const SizedBox(
                    width: 50.0,
                  ),
                  OutlinedButton(
                    child: const Text('Clear'),
                    onPressed: clearWindow,
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 8,
              child: Card(
                margin: const EdgeInsets.all(10.0),
                child: ListView.builder(
                    controller: logWindowController,
                    itemCount: receiveDataList.length,
                    itemBuilder: (context, index) {
                      if (!_scrollEnable) {
                      logWindowController.animateTo(logWindowController.position.maxScrollExtent,
                                            curve:Curves.easeOut,
                                            duration: const Duration(milliseconds: 100),);
                      }
                      /*
                      OUTPUT for raw bytes 
                      return Text(receiveDataList[index].toString()); */
                      
                      /* output for string */
                      return Text(String.fromCharCodes(receiveDataList[index]).replaceAll('\n', '')); 
                    },),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Flexible(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10.0),
                    child: TextField(
                      onSubmitted: processCmdCompletion,
                      enabled: (_serialPort != null && _serialPort!.isOpen)
                          ? true
                          : false,
                      controller: textInputCtrl,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ),
                Flexible(
                  child: TextButton.icon(
                    onPressed: sendSerialOutput,
                    icon: const Icon(Icons.send),
                    label: const Text("Send"),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void setupSerialPort() {
    if (_serialPort == null) {
      return;
    }
    if (_serialPort!.isOpen) {
      _serialPort!.close();
      debugPrint('${_serialPort!.name} closed!');
    } else {
      if (_serialPort!.open(mode: SerialPortMode.readWrite)) {
        SerialPortConfig config = _serialPort!.config;
        // https://www.sigrok.org/api/libserialport/0.1.1/a00007.html#gab14927cf0efee73b59d04a572b688fa0
        // https://www.sigrok.org/api/libserialport/0.1.1/a00004_source.html
        config.baudRate = 57600;
        config.parity = 0;
        config.bits = 8;
        config.cts = 0;
        config.rts = 0;
        config.stopBits = 1;
        config.xonXoff = 0;
        _serialPort!.config = config;

        if (_serialPort!.isOpen) {
          debugPrint('${_serialPort!.name} opened!');
        }

        final reader = SerialPortReader(_serialPort!);
        processSerialInput(reader);
      }
    }
    setState(() {});
  }

  void processSerialInput(SerialPortReader reader) {
    reader.stream.listen((data) {
      // debugPrint('received: $data');
      receiveDataList.add(data);
      setState(() {});
    }, onError: (error) {
      if (error is SerialPortError) {
        debugPrint(
            'error: ${cp949.decodeString(error.message)}, code: ${error.errorCode}');
      }
    });
  }

  void sendSerialOutput() {
    var data = textInputCtrl.text;
    if (!data.contains('\n')) {
      data += '\n';
    }
    SerialPort port = _serialPort!;
    if (port != null && port.isOpen) {
      var writeLen = port.write(Uint8List.fromList(data.codeUnits));
      debugPrint('Wrote: $data, Bytes sent: $writeLen');
      if (writeLen == data.length) {
        setState(() {
          textInputCtrl.text = '';
        });
      }
    }
  }

  void changeScrollSetting(bool? newValue) {
    _scrollEnable = newValue as bool;
  }

  void clearWindow() {
    receiveDataList.clear();
  }

  void processCmdCompletion(text) {
    // debugPrint(text);
    sendSerialOutput();
  }
}
