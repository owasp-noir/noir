import 'package:args/args.dart';
import 'dart:io';

void main(List<String> args) {
  final parser = ArgParser();
  parser.addFlag('verbose', abbr: 'v');
  parser.addOption('name', abbr: 'n');

  final serve = parser.addCommand('serve');
  serve.addOption('port');

  final token = Platform.environment['API_TOKEN'];
  print(token);
}
