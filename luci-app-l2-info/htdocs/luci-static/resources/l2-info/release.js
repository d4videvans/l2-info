/* SPDX-License-Identifier: Apache-2.0 */
/* Public pre-upstream test identity. Keep packageVersion in sync with the
 * LuCI Makefile; tests/run.sh enforces that relationship and the public docs. */

'use strict';
'require baseclass';

return baseclass.extend({
	tag: 'v0.1.0-rc3',
	packageVersion: '0.1.0-r3'
});
