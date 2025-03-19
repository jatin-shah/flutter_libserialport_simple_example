import 'dart:convert';
import 'dart:ffi';
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
        debugPrint('${++i}) $name');
        debugPrint('\tDescription: ${cp949.decodeString(sp.description ?? '')}');
        debugPrint('\tManufacturer: ${sp.manufacturer}');
        debugPrint('\tSerial Number: ${sp.serialNumber}');
        debugPrint('\tProduct ID: 0x${sp.productId?.toRadixString(16) ?? 00}');
        debugPrint('\tVendor ID: 0x${sp.vendorId?.toRadixString(16) ?? 00}');
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
                      /* OUTPUT for raw bytes */
                      // return Text(receiveDataList[index].toString()); 
                      return Text(receiveDataList[index].map((byte)=> byte.toRadixString(16).toUpperCase().padLeft(2, '0')).join(' ')); 
                      
                      /* output for string 
                      return Text(String.fromCharCodes(receiveDataList[index]).replaceAll('\n', ''));  */
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
                    onPressed: sendTestData, //sendSerialOutput,
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
        config.baudRate = 115200;
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

  void sendTestData() {
    Uint8List data = Uint8List.fromList([0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F, 0x10, 0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17, 0x18, 0x19, 0x1A, 0x1B, 0x1C, 0x1D, 0x1E, 0x1F, 0x20, 0x21, 0x22, 0x23, 0x24, 0x25, 0x26, 0x27, 0x28, 0x29, 0x2A, 0x2B, 0x2C, 0x2D, 0x2E, 0x2F, 0x30, 0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39, 0x3A, 0x3B, 0x3C, 0x3D, 0x3E, 0x3F, 0x40, 0x41, 0x42, 0x43, 0x44, 0x45, 0x46, 0x47]);
    SerialPort port = _serialPort!;
    if (port != null && port.isOpen) {
      var writeLen = port.write(data);
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
    setState(() {
      receiveDataList.clear();
    });
  }

  void processCmdCompletion(text) {
    // debugPrint(text);
    // sendSerialOutput();
    sendTestData();
  }
}
