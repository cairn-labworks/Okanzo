import 'package:flutter/material.dart';

import '../../domain/model/release_notes.dart';
import '../../l10n/app_localizations.dart';
import 'type_icons.dart';

Future<void> showWhatsNewDialog(
  BuildContext context, {
  ReleaseNotes? releaseNotes,
}) {
  final ReleaseNotes notes = releaseNotes ?? AppReleaseNotes.current;
  return showDialog<void>(
    context: context,
    builder: (BuildContext dialogContext) =>
        WhatsNewDialog(releaseNotes: notes),
  );
}

class WhatsNewDialog extends StatelessWidget {
  const WhatsNewDialog({required this.releaseNotes, super.key});

  final ReleaseNotes releaseNotes;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return AlertDialog(
      title: Text(
        "What's new in {version}"
            .tr(context)
            .replaceAll('{version}', releaseNotes.version),
      ),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'Here are the key highlights from this update.'.tr(context),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              for (
                int i = 0;
                i < releaseNotes.highlights.length;
                i++
              ) ...<Widget>[
                if (i > 0) const SizedBox(height: 12),
                _HighlightTile(highlight: releaseNotes.highlights[i]),
              ],
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('Got it'.tr(context)),
        ),
      ],
    );
  }
}

class _HighlightTile extends StatelessWidget {
  const _HighlightTile({required this.highlight});

  final ReleaseHighlight highlight;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(
            releaseHighlightIcon(highlight.icon),
            size: 18,
            color: theme.colorScheme.primary,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                highlight.title.tr(context),
                style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                highlight.description.tr(context),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
