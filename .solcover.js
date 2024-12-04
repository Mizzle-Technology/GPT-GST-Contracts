module.exports = {
  skipFiles: [
    'mocks/', // Ignore all files in the mocks directory
    'test/', // Ignore test files
    'interfaces/', // Ignore interface files
  ],
  configureYulOptimizer: true,
  mocha: {
    timeout: 100000,
  },
};
