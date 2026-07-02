import 'package:fluent_ui/fluent_ui.dart';
import 'package:kyber_launcher/core/config/colors.dart';
import 'package:kyber_launcher/shared/ui/ui.dart';

class ModerationInputDialog extends StatefulWidget {
  const ModerationInputDialog({
    this.title = 'REASON',
    this.prompt = 'Enter the reason:',
    this.placeholder = 'Optional',
    this.submitText = 'Submit',
    super.key,
  });

  final String title;
  final String prompt;
  final String placeholder;
  final String submitText;

  @override
  State<ModerationInputDialog> createState() => _ModerationInputDialogState();
}

class _ModerationInputDialogState extends State<ModerationInputDialog> {
  String value = '';

  @override
  Widget build(BuildContext context) {
    return KyberContentDialog(
      constraints: const BoxConstraints(maxWidth: 600, maxHeight: 400),
      title: Text(widget.title.toUpperCase()),
      content: Column(
        children: [
          Text(
            widget.prompt,
            style: const TextStyle(color: kWhiteColor),
          ),
          const SizedBox(height: 8),
          KyberInput(
            placeholder: widget.placeholder,
            onChanged: (value) {
              this.value = value;
            },
          ),
        ],
      ),
      actions: [
        KyberButton(
          onPressed: () {
            Navigator.of(context).pop();
          },
          text: 'Cancel',
        ),
        KyberButton(
          onPressed: () {
            Navigator.of(context).pop(value);
          },
          text: widget.submitText,
        ),
      ],
    );
  }
}
