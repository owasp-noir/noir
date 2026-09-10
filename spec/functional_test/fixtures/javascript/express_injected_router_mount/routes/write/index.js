'use strict';

const Write = module.exports;

Write.reload = async (params) => {
	const { router } = params;

	router.use('/api/v3/users', require('./users')());
	router.use('/api/v3/groups', require('./groups')());
};
