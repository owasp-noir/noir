// An Elysia server file that also imports react (SSR) is still a server file.
import { Elysia } from 'elysia'
import { renderToString } from 'react-dom/server'
import React from 'react'

export const page = new Elysia().get('/elysia-page', () =>
  renderToString(React.createElement('div', null, 'hi'))
)
