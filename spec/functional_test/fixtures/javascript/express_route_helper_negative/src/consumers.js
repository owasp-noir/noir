'use strict';

const axios = require('axios');
const express = require('express');
const app = require('./server');
const { request, fetchJson, readCache, dispatch, mountAt } = require('./http-client');

async function loadEverything() {
	await request(axios, 'get', '/api/remote/users');
	await request(axios, 'post', '/api/remote/users');
	await fetchJson(axios, '/api/remote/config');
	readCache(new Map(), '/api/remote/cached');
	dispatch({}, 'get', '/api/remote/dispatched');
	await Promise.all([1, 2]);
}

mountAt(app, '/mounted', express.Router());

module.exports = loadEverything;
