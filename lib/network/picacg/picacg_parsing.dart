import '../json_value.dart';
import 'picacg_models.dart';

/// Parses one Picacg episode page without performing network I/O.
///
/// This internal parser is public only so the network adapter and package tests share
/// one response boundary. It is intentionally not exported by the network facade.
({List<PicacgEpisode> episodes, int pages})? parsePicacgEpisodePage(
  Object? rawResponse,
) {
  if (rawResponse is! Map) return null;
  final rawData = rawResponse['data'];
  if (rawData is! Map) return null;
  final rawEps = rawData['eps'];
  if (rawEps is! Map) return null;
  final epsRoot = jsonMap(rawEps);

  var pages = jsonInt(epsRoot['pages'], fallback: 1);
  if (pages < 1) pages = 1;

  final episodes = <PicacgEpisode>[];
  for (final rawEpisode in jsonList(epsRoot['docs'])) {
    if (rawEpisode is! Map) continue;
    final episode = jsonMap(rawEpisode);
    final order = jsonInt(episode['order'], fallback: -1);
    if (order <= 0) continue;
    final title = jsonString(episode['title']);
    episodes.add(PicacgEpisode(
      title: title.isEmpty ? '第$order' : title,
      order: order,
    ));
  }
  return (episodes: episodes, pages: pages);
}
