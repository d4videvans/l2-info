from pathlib import Path
import runpy

p = Path('luci-app-l2-info/htdocs/luci-static/resources/l2-info/release.js')
p.write_text("""/* SPDX-License-Identifier: Apache-2.0 */
/* Public pre-upstream test identity. Keep packageVersion in sync with the
 * LuCI Makefile; tests/run.sh enforces that relationship and the public docs. */

'use strict';
'require baseclass';

return baseclass.extend({
\ttag: 'v0.1.0-rc3',
\tpackageVersion: '0.1.0-r3'
});
""")
runpy.run_path('.github/rc3-feedback.py', run_name='__main__')
