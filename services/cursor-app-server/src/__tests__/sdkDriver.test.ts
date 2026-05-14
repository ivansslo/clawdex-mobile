import { buildLocalCursorAgentOptions } from '../sdkDriver.js';

describe('CursorSdkDriver', () => {
  it('pins new local agents to the requested Cursor SDK workspace', () => {
    expect(buildLocalCursorAgentOptions({ cwd: '/workspace/launchkit' })).toEqual({
      local: {
        cwd: '/workspace/launchkit',
      },
      platform: {
        workspaceRef: '/workspace/launchkit',
      },
    });
  });

  it('can resume from an existing SDK store while running in the requested workspace', () => {
    expect(
      buildLocalCursorAgentOptions({
        cwd: '/workspace/launchkit',
        storeCwd: '/workspace/clawdex-mobile',
      })
    ).toEqual({
      local: {
        cwd: '/workspace/launchkit',
      },
      platform: {
        workspaceRef: '/workspace/clawdex-mobile',
      },
    });
  });
});
