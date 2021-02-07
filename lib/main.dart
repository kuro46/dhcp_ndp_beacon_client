import 'dart:ui';

import 'package:flutter/material.dart';
import 'dart:convert' as convert;
import 'package:http/http.dart' as http;

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

  ExpansionPanel _createExpansionPanel(_ClientInfo client) {
    String leaseStr = "";
    if (client.lease != null) {
      leaseStr = "Hostname: ${client.lease.hostName}\n"
          "IPv4 Address: ${client.lease.ipv4Address}\n"
          "IPv4 Address Expire: ${client.lease.ipv4AddressExpire}\n";
    }
    String ipv6Str =
        "IPv6 Addresses:\n  ${client.ipv6Addresses.join("\n  ")}\n";
    return ExpansionPanel(
        headerBuilder: (context, isExpanded) {
          String title = client.mac;
          if (client.lease != null && client.lease.hostName != null) {
            title = client.lease.hostName;
          }
          return Text(title);
        },
        isExpanded: client.expanded ?? false,
        canTapOnHeader: true,
        body: Padding(
          child: Align(
            child: Text("Mac: ${client.mac}\n$leaseStr$ipv6Str",
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
