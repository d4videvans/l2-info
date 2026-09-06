// SPDX-License-Identifier: Apache-2.0
// Temporary synthetic ubus surface used only by tools/install-screenshot-demo.sh.

'use strict';

const SNAPSHOT = '/usr/share/l2-info/demo-snapshot.uc';

return {
	'l2-info-demo': {
		snapshot: {
			call: () => loadfile(SNAPSHOT)()
		}
	}
};
