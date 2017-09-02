import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

TextStyle smallText(BuildContext context) => Theme.of(context).textTheme.body1.copyWith(color: Colors.black45);
TextStyle mediumText(BuildContext context) => Theme.of(context).textTheme.headline.copyWith(fontSize: 18.0, color: Colors.black54);

void openPrivacyAndContact() {
	launch("https://husbot.tutorialfactory.org/legal/privacy.html");
}

TextSpan createLink({String url, String text, TextStyle style}) {
	text = text ?? url;

	return new TextSpan(text: text, style: style,
			recognizer: new TapGestureRecognizer()..onTap = () => launch(url));
}

Widget getEmptyList([String msg = "Keine Daten verfügbar", String subMsg = "Warte oder führe eine Aktualisierung durch"]) {
	return new Center(
		child: new Column(
			mainAxisAlignment: MainAxisAlignment.center,
			children: [
				new Container(
					padding: const EdgeInsets.only(bottom: 8.0),
					child: new Text(
						msg,
						textAlign: TextAlign.center,
						style: new TextStyle(
							fontSize: 32.0,
							fontWeight: FontWeight.bold,
							color: Colors.grey[500]
						),
					),
				),
				new Text(
					subMsg,
					textAlign: TextAlign.center,
					style: new TextStyle(
						fontSize: 16.0
					)
				)
			]
		)
	);
}

class RightArrowPainter extends CustomPainter {

	static const AR_SIZE = 8.0;

	final Color _color;

	const RightArrowPainter(this._color);

  @override
  void paint(Canvas canvas, Size size) {
  	//The arrow consists of a rectangle on the left and a triangle on the right
		var path = new Path();
		path.moveTo(0.0, 0.0); //top left corner, rectangle
		path.lineTo(size.width - AR_SIZE, 0.0); //top right corner, rectangle
		path.lineTo(size.width, size.height / 2); //triangle
		path.lineTo(size.width - AR_SIZE, size.height); //bottom right corner, rectangle
		path.lineTo(0.0, size.height); //top right corner, rectangle
		path.lineTo(0.0, 0.0); //finish

		var paint = new Paint();
		paint.color = _color;

		canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) {
  	if (oldDelegate is RightArrowPainter) {
  		return oldDelegate._color != _color;
		}
    return false;
  }
}

class MultAnimation extends Animation<double>
		with AnimationLazyListenerMixin, AnimationLocalStatusListenersMixin {

	final Animation<double> parent;
	final double factor;

	/// Creates a animation multiplying another.
	///
	/// The parent argument must not be null.
	MultAnimation(this.parent, this.factor)
			: assert(parent != null);

	@override
	void addListener(VoidCallback listener) {
		didRegisterListener();
		parent.addListener(listener);
	}

	@override
	void removeListener(VoidCallback listener) {
		parent.removeListener(listener);
		didUnregisterListener();
	}

	@override
	void didStartListening() {
		parent.addStatusListener(_statusChangeHandler);
	}

	@override
	void didStopListening() {
		parent.removeStatusListener(_statusChangeHandler);
	}

	void _statusChangeHandler(AnimationStatus status) {
		notifyStatusListeners(status);
	}

	@override
	AnimationStatus get status => parent.status;

	@override
	double get value => factor * parent.value;
}