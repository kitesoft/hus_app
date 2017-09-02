import 'dart:async';
import 'dart:io';
import 'package:azuchath_flutter/logic/azuchath.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:path_provider/path_provider.dart';

class FirebaseManager {

	final Azuchath _azu;
	final FirebaseMessaging messaging = new FirebaseMessaging();

	///The firebase token that can be used by the server to contact this device
	///When it's changed or first created, we need to upload it to the server in
	///order to receive push-notifications
	String _localToken;
	///Used to store the current fcm token when it's received before we have
	///loaded the file with the token saved on the device. If it is needed, we
	///will call a token change with it to check if there has been an update.
	String _receivedCurrentToken;
	get token => _localToken;

	bool initialized = false;

	File _tokenFile;

	FirebaseManager(this._azu);

	Future init() async {
		messaging.configure(onMessage: _handleMessage, onResume: _handleMessage, onLaunch: _handleMessage);
		messaging.onTokenRefresh.listen(_onTokenChanged);

		var dir = await getApplicationDocumentsDirectory();
		_tokenFile = new File("${dir.path}/fcm_token");

		if (! await _tokenFile.exists()) {
			await _tokenFile.create(recursive: true);
		} else {
			_localToken = await _tokenFile.readAsString();
		}

		//Fetch the token for the first time if we do not have it locally
		if (_localToken == null || _localToken.isEmpty) {
			messaging.getToken().then(_onTokenChanged);
		}

		initialized = true;
		if (_receivedCurrentToken != null) {
			_onTokenChanged(_receivedCurrentToken);
		}
	}

	void requestMsgPerms() {
		messaging.requestNotificationPermissions();
	}

	Future _handleMessage(Map<String, dynamic> data) async {
		_azu.syncWithServer();

		print("Received firebase message: " + data.toString());
	}

	void _onTokenChanged(String token) {
		if (!initialized) {
			_receivedCurrentToken = token;
			return;
		}

		if (_localToken != token && token != null)
			syncToken(token);
	}

	Future syncToken(String token) async {
		_localToken = token;
		print("FCM token has changed, uploading to server");
		if (_azu.data.isLoggedIn) {
			await _azu.api.writeFcmToken(token);
			await _tokenFile.writeAsString(token);
		}
	}
}