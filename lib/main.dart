import 'dart:collection';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'dart:convert' as convert;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'dhcp_ndp_beacon client',
      theme: ThemeData.light(),
      darkTheme: ThemeData.dark(),
      themeMode: ThemeMode.system,
      home: MainPage(),
    );
  }
}

class MainPage extends StatefulWidget {
  @override
  _MainPageState createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  final HostNameCache _hostNameCache = HostNameCache();
  List<_ClientInfo> _clients;

  Future<List<_ClientInfo>> _retrieveClients() async {
    final response = await http.get("http://192.168.0.1/api/status");
    if (response.statusCode != 200) return null;
    final List<_ClientInfo> clients = List();
    final Map<String, dynamic> json = convert.jsonDecode(response.body);
    for (var value in json.entries) {
      final mac = value.key;
      final Map<String, dynamic> leasesAndNeighbors = value.value;
      final Map<String, dynamic> rawLease = leasesAndNeighbors["dhcp_lease"];
      _DHCPLease lease;
      if (rawLease != null) {
        final String ipv4Address = rawLease["ipv4_address"];
        final String ipv4AddressExpire = rawLease["end"];
        final String hostName = rawLease["host_name"];
        lease = _DHCPLease(hostName, ipv4Address, ipv4AddressExpire);
      }
      final List<dynamic> rawIpv6Addresses = leasesAndNeighbors["ndp_entries"];
      final List<String> ipv6Addresses = List();
      for (var value in rawIpv6Addresses) {
        final Map<String, dynamic> rawIpv6Address = value;
        ipv6Addresses.add(rawIpv6Address["ipv6_address"]);
      }
      clients.add(_ClientInfo(mac, lease, ipv6Addresses, false));
    }
    return clients;
  }

  @override
  void initState() {
    super.initState();
    _retrieveClients().then((value) {
      setState(() {
        _clients = value;
      });
    });
    HostNameCache.readFromFile().then((entries) {
      setState(() {
        for (var entry in entries) {
          _hostNameCache.putEntry(entry);
        }
      });
    });
  }

  Future _updateStatus() async {
    setState(() {
      _clients = null;
    });
    _retrieveClients().then((value) {
      setState(() {
        _clients = value;
      });
    });
  }

  Future<String> _showHostNameInputDialog(
      BuildContext context, String currentText) async {
    final textController = TextEditingController(text: currentText ?? "");
    final textField = new SimpleDialogOption(
      child: TextField(
        controller: textController,
        decoration: InputDecoration(hintText: "Enter hostname here"),
      ),
    );
    final okButton = FlatButton(
        onPressed: () {
          Navigator.pop<String>(context, textController.text);
        },
        child: Text("OK"));
    final cancelButton = FlatButton(
        onPressed: () {
          Navigator.pop<String>(context, null);
        },
        child: Text("Cancel"));
    final alertDialog = AlertDialog(
      title: Text("Change hostname"),
      content: textField,
      actions: [cancelButton, okButton],
    );
    return await showDialog(
        context: context, builder: (context) => alertDialog);
  }

  String _convertClientToPanelBody(_ClientInfo client) {
    String leaseStr = "DHCP: None\n";
    if (client.lease != null) {
      leaseStr = "DHCP:\n"
          "  Hostname: ${client.lease.hostName ?? "Unknown"}\n"
          "  Address: ${client.lease.ipv4Address}\n"
          "  Expire At: ${client.lease.ipv4AddressExpire}\n";
    }
    String ipv6Str = "NDP Entries: None\n";
    if (client.ipv6Addresses.isNotEmpty) {
      ipv6Str = "NDP Entries:\n  - ${client.ipv6Addresses.join("\n  - ")}\n";
    }
    return "Mac: ${client.mac}\n$leaseStr$ipv6Str";
  }

  ExpansionPanel _createExpansionPanel(_ClientInfo client) {
    return ExpansionPanel(
        headerBuilder: (context, isExpanded) {
          String mac = client.mac;
          final hostName = _hostNameCache.get(mac);
          final title =
              mac + (hostName == null ? "" : " [${hostName.hostName}]");
          return GestureDetector(
            child: Text(title),
            onLongPress: () async {
              final String newHostname = await _showHostNameInputDialog(
                  context, hostName == null ? "" : hostName.hostName);
              if (newHostname == null) {
                return;
              }
              _hostNameCache.put(mac, newHostname);
              _hostNameCache.writeToFile();
              setState(() {});
            },
          );
        },
        isExpanded: client.expanded ?? false,
        canTapOnHeader: true,
        body: Padding(
          child: Align(
            child: Text(_convertClientToPanelBody(client),
                textAlign: TextAlign.left),
            alignment: Alignment.topLeft,
          ),
          padding: EdgeInsets.all(4),
        ));
  }

  @override
  Widget build(BuildContext context) {
    var body;
    if (_clients == null) {
      body = Center(child: CircularProgressIndicator());
    } else {
      final panels = _clients.map(_createExpansionPanel).toList();
      body = RefreshIndicator(
        child: Padding(
          child: ListView(children: [
            ExpansionPanelList(
              expansionCallback: (panelIndex, isExpanded) {
                setState(() {
                  _clients[panelIndex].expanded = !isExpanded;
                });
              },
              children: panels,
            )
          ]),
          padding: EdgeInsets.all(4),
        ),
        onRefresh: _updateStatus,
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text("dhcp_ndp_beacon client"),
      ),
      body: body,
    );
  }
}

class HostNameCache {
  final Map<String, HostNameCacheEntry> _entries = HashMap();

  HostNameCacheEntry get(String mac) {
    return _entries[mac];
  }

  void put(String mac, String hostName) {
    putEntry(HostNameCacheEntry(mac, hostName));
  }

  void putEntry(HostNameCacheEntry entry) {
    _entries[entry.mac] = entry;
  }

  HostNameCacheEntry getOr(String mac, String Function() ifAbsent) {
    var entry = _entries[mac];
    if (entry == null) {
      final generated = ifAbsent();
      if (generated != null) {
        entry = HostNameCacheEntry(mac, generated);
      }
    }
    return entry;
  }

  static Future<File> getFile() async {
    final dataFolder = await getApplicationDocumentsDirectory();
    print(dataFolder);
    final file = File("${dataFolder.path}/hostname_cache.json");
    print(file);
    return file;
  }

  static Future<List<HostNameCacheEntry>> readFromFile() async {
    final file = await getFile();
    final Map<String, dynamic> decoded =
        convert.jsonDecode(await file.readAsString());
    final List<HostNameCacheEntry> result = List();
    decoded.forEach((key, value) {
      result.add(HostNameCacheEntry(key, value));
    });
    return result;
  }

  void writeToFile() async {
    final file = await getFile();
    final Map<String, String> serializable = HashMap();
    for (final value in _entries.values) {
      serializable[value.mac] = value.hostName;
    }
    await file.writeAsString(convert.jsonEncode(serializable));
  }
}

class HostNameCacheEntry {
  final String mac;
  final String hostName;

  HostNameCacheEntry(this.mac, this.hostName);
}

class _ClientInfo {
  final String mac;
  final _DHCPLease lease;
  final List<String> ipv6Addresses;
  bool expanded = false;

  _ClientInfo(this.mac, this.lease, this.ipv6Addresses, this.expanded);
}

class _DHCPLease {
  final String hostName;
  final String ipv4Address;
  final String ipv4AddressExpire;

  _DHCPLease(this.hostName, this.ipv4Address, this.ipv4AddressExpire);
}
