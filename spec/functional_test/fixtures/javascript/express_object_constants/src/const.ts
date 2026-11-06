const prefix = '/experience';

export const experienceRoutes = Object.freeze({
  prefix,
  verification: `${prefix}/verification`,
  mfa: `${prefix}/profile/mfa`,
  computed: buildPath(prefix),
  nested: { deep: '/deep' },
});

export const accountApiPrefix = '/my-account';
