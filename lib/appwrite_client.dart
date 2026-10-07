import 'package:appwrite/appwrite.dart';

const _endpoint = String.fromEnvironment(
  'APPWRITE_ENDPOINT',
  defaultValue: 'https://sgp.cloud.appwrite.io/v1',
);
const _projectId = String.fromEnvironment(
  'APPWRITE_PROJECT_ID',
  defaultValue: '6ac4baef0010879da982',
);

/// Public aliases for building REST URLs (e.g. storage file previews).
const appwriteEndpoint = _endpoint;
const appwriteProjectId = _projectId;

final client = Client()
  ..setEndpoint(_endpoint)
  ..setProject(_projectId);
