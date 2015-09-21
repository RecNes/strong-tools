var wrapped = require('./lib/wrapped');

module.exports = {
  lint: require('./lib/lint'),
  cla: require('./lib/cla'),
  Project: require('./lib/project'),
  info: require('./lib/info'),
  version: require('./lib/version'),
  semver: wrapped('semver/bin/semver'),
};

if (require('child_process').execSync) {
  module.exports.license =  require('./lib/license');
}
