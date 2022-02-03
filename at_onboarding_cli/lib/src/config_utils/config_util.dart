import 'package:at_utils/at_utils.dart';
import 'package:yaml/yaml.dart';

class ConfigUtil {
  static final ApplicationConfiguration appConfig =
      ApplicationConfiguration('lib/config/config.yaml');

  static YamlMap? getConfigYaml() {
    return appConfig.getYaml();
  }
}
