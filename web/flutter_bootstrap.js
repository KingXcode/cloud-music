{{flutter_js}}
{{flutter_build_config}}
// Updates are owned by app_updates.js. Flutter's generated offline worker must
// not eagerly switch a running player or maintain a second, unverified cache.
_flutter.loader.load({
  config: { canvasKitBaseUrl: new URL('canvaskit/', document.baseURI).href }
});
