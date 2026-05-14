import { constants } from 'node:fs';
import { access, readdir } from 'node:fs/promises';
import { homedir } from 'node:os';
import { dirname, join } from 'node:path';

export interface CursorTranscriptWorkspaceOptions {
  agentId: string;
  projectsDir?: string;
  knownCwds: string[];
}

export async function findCursorTranscriptWorkspaceCwd({
  agentId,
  projectsDir = defaultCursorProjectsDir(),
  knownCwds,
}: CursorTranscriptWorkspaceOptions): Promise<string | null> {
  const projectDirNames = await findTranscriptProjectDirNames(projectsDir, agentId);
  for (const projectDirName of projectDirNames) {
    const cwd = await resolveProjectDirNameToCwd(projectDirName, knownCwds);
    if (cwd) {
      return cwd;
    }
  }
  return null;
}

export function cursorProjectDirName(cwd: string): string {
  return cwd.replace(/^\/+/, '').replaceAll('/', '-');
}

function defaultCursorProjectsDir(): string {
  return join(homedir(), '.cursor', 'projects');
}

async function findTranscriptProjectDirNames(
  projectsDir: string,
  agentId: string
): Promise<string[]> {
  let entries;
  try {
    entries = await readdir(projectsDir, { withFileTypes: true });
  } catch {
    return [];
  }

  const matches: string[] = [];
  for (const entry of entries) {
    if (!entry.isDirectory()) {
      continue;
    }
    const transcriptPath = join(
      projectsDir,
      entry.name,
      'agent-transcripts',
      agentId,
      `${agentId}.jsonl`
    );
    if (await pathExists(transcriptPath)) {
      matches.push(entry.name);
    }
  }
  return matches;
}

async function resolveProjectDirNameToCwd(
  projectDirName: string,
  knownCwds: string[]
): Promise<string | null> {
  for (const cwd of knownCwds) {
    if (cursorProjectDirName(cwd) === projectDirName) {
      return cwd;
    }
  }

  for (const searchRoot of candidateSearchRoots(knownCwds)) {
    const direct = await findWorkspaceChild(searchRoot, projectDirName);
    if (direct) {
      return direct;
    }
  }

  return null;
}

function candidateSearchRoots(knownCwds: string[]): string[] {
  const roots = new Set<string>();
  for (const cwd of knownCwds) {
    let root = dirname(cwd);
    for (let depth = 0; depth < 2; depth += 1) {
      if (!root || root === '.' || root === dirname(root)) {
        break;
      }
      roots.add(root);
      root = dirname(root);
    }
  }
  return [...roots];
}

async function findWorkspaceChild(
  searchRoot: string,
  projectDirName: string
): Promise<string | null> {
  let entries;
  try {
    entries = await readdir(searchRoot, { withFileTypes: true });
  } catch {
    return null;
  }

  for (const entry of entries) {
    if (!entry.isDirectory()) {
      continue;
    }
    const candidate = join(searchRoot, entry.name);
    if (cursorProjectDirName(candidate) === projectDirName) {
      return candidate;
    }
  }

  for (const entry of entries) {
    if (!entry.isDirectory()) {
      continue;
    }
    const childRoot = join(searchRoot, entry.name);
    const direct = await findWorkspaceGrandchild(childRoot, projectDirName);
    if (direct) {
      return direct;
    }
  }

  return null;
}

async function findWorkspaceGrandchild(
  searchRoot: string,
  projectDirName: string
): Promise<string | null> {
  let entries;
  try {
    entries = await readdir(searchRoot, { withFileTypes: true });
  } catch {
    return null;
  }

  for (const entry of entries) {
    if (!entry.isDirectory()) {
      continue;
    }
    const candidate = join(searchRoot, entry.name);
    if (cursorProjectDirName(candidate) === projectDirName) {
      return candidate;
    }
  }
  return null;
}

async function pathExists(path: string): Promise<boolean> {
  try {
    await access(path, constants.F_OK);
    return true;
  } catch {
    return false;
  }
}
