/** @type {import('dependency-cruiser').IConfiguration} */
module.exports = {
  forbidden: [
    {
      // Services integrate over HTTP per the contracts they publish, never
      // by importing each other's code directly. The `$1` back-reference
      // ties the match in `from` to the negative lookahead in `to`: a
      // module under services/<name>/ may import anything except another
      // services/<other-name>/ path (importing its own service is fine).
      name: 'services-no-cross-imports',
      severity: 'error',
      comment:
        'A service may not import from another service. Services talk to ' +
        'each other over HTTP per their published contracts, not by ' +
        "reaching into a sibling service's source.",
      from: { path: '^services/([^/]+)/' },
      to: { path: '^services/(?!$1/)[^/]+/' },
    },
    {
      // The only cross-package import services are allowed is the shared
      // contracts package (CLAUDE.md: "the only cross-service import
      // allowed"). Anything else under packages/* is off limits to
      // services.
      name: 'services-only-contracts-from-packages',
      severity: 'error',
      comment:
        'A service may only import packages/contracts from packages/*. ' +
        'No other package is a sanctioned surface between services.',
      from: { path: '^services/' },
      to: { path: '^packages/(?!contracts/)[^/]+/' },
    },
  ],
  options: {
    // Which modules not to follow further when encountered.
    doNotFollow: {
      path: 'node_modules',
    },

    // TypeScript project file used for both compilation and resolution
    // (workspace packages resolve each other via package.json `exports`,
    // which needs a tsconfig-aware resolver to follow).
    tsConfig: {
      fileName: 'tsconfig.base.json',
    },

    enhancedResolveOptions: {
      exportsFields: ['exports'],
      conditionNames: ['import', 'require', 'node', 'default', 'types'],
    },
  },
};
