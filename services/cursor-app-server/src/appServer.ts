import { EventEmitter } from 'node:events';
import { readFile } from 'node:fs/promises';
import { extname } from 'node:path';

import { findCursorTranscriptWorkspaceCwd } from './cursorWorkspace.js';
import {
  parseListParams,
  parseThreadIdParams,
  parseThreadStartParams,
  parseTurnStartParams,
} from './input.js';
import {
  isGenericCursorAgentName,
  messagesToTurns,
  projectAgentInfoToThread,
  readMessageText,
  streamMessageToThreadItem,
  toPreview,
} from './projection.js';
import { CursorSdkDriver } from './sdkDriver.js';
import type {
  AppServerNotification,
  CursorAgentHandle,
  CursorAgentInfo,
  CursorAgentMessage,
  CursorAppServerOptions,
  CursorDriver,
  CursorRunHandle,
  CursorRunResult,
  CursorStreamMessage,
  ModelSelection,
  ThreadItem,
  ThreadTurn,
} from './types.js';

interface LiveThreadState {
  agent: CursorAgentHandle;
  info: CursorAgentInfo;
  cwd: string;
  storeCwd: string;
  model?: ModelSelection;
  turns: ThreadTurn[];
  activeRun?: CursorRunHandle;
  nameLocked: boolean;
}

interface ThreadWorkspace {
  cwd: string;
  storeCwd: string;
}

type NotificationListener = (notification: AppServerNotification) => void;

export class CursorAppServer {
  private readonly runtime: 'local';
  private readonly driver: CursorDriver;
  private readonly configuredCwd: string | null;
  private readonly apiKey: string | null;
  private readonly defaultModel: string | null;
  private readonly cursorProjectsDir: string | undefined;
  private readonly events = new EventEmitter();
  private readonly liveThreads = new Map<string, LiveThreadState>();
  private readonly knownThreadCwds = new Map<string, string>();
  private readonly knownThreadStoreCwds = new Map<string, string>();

  constructor(options: CursorAppServerOptions) {
    if (options.runtime !== 'local') {
      throw new Error(`unsupported Cursor runtime: ${String(options.runtime)}`);
    }

    this.runtime = options.runtime;
    this.driver = options.driver ?? new CursorSdkDriver();
    this.configuredCwd = normalizeString(options.cwd);
    this.apiKey = normalizeString(options.apiKey);
    this.defaultModel = normalizeString(options.defaultModel);
    this.cursorProjectsDir = normalizeString(options.cursorProjectsDir) ?? undefined;
  }

  onNotification(listener: NotificationListener): () => void {
    this.events.on('notification', listener);
    return () => {
      this.events.off('notification', listener);
    };
  }

  async request(method: string, params?: unknown): Promise<Record<string, unknown>> {
    switch (method) {
      case 'thread/list':
        return this.listThreads(params);
      case 'thread/loaded/list':
        return this.listLoadedThreads();
      case 'thread/read':
        return this.readThread(params);
      case 'thread/start':
        return this.startThread(params);
      case 'turn/start':
        return this.startTurn(params);
      case 'turn/interrupt':
        return this.interruptTurn(params);
      case 'model/list':
        return this.listModels();
      case 'initialize':
      case 'initialized':
        return this.initialize();
      default:
        throw new Error(`unsupported Cursor app-server method: ${method}`);
    }
  }

  private async listThreads(params: unknown): Promise<Record<string, unknown>> {
    const parsed = parseListParams(params);
    this.requireApiKey();
    const requestedCwd = normalizeString(parsed.cwd);
    const cwds = requestedCwd
      ? uniqueStrings([requestedCwd, ...this.listKnownWorkspaceCwds()])
      : this.listKnownWorkspaceCwds();
    const limit = parsed.limit ?? 100;
    const entries = new Map<string, CursorAgentInfo>();
    let nextCursor: string | null = null;

    for (const cwd of cwds) {
      const result = await this.driver.listAgents({
        cwd,
        limit,
        cursor: cwds.length === 1 ? parsed.cursor : undefined,
      });

      if (cwds.length === 1) {
        nextCursor = result.nextCursor ?? null;
      }

      for (const agent of result.items) {
        const effectiveCwd = await this.resolveAgentEffectiveCwd(agent, cwd, requestedCwd);
        if (requestedCwd && effectiveCwd !== requestedCwd) {
          continue;
        }
        const projectedAgent = { ...agent, cwd: effectiveCwd };
        this.rememberAgentCwd(projectedAgent, cwd, effectiveCwd);
        const existing = entries.get(agent.agentId);
        if (!existing || projectedAgent.lastModified > existing.lastModified) {
          entries.set(agent.agentId, projectedAgent);
        }
      }
    }

    return {
      data: [...entries.values()]
        .sort(compareCursorAgentsByUpdatedAtDesc)
        .slice(0, limit)
        .map((agent) =>
          projectAgentInfoToThread(
            agent,
            this.resolveKnownThreadWorkspace(agent.agentId, agent.cwd ?? requestedCwd).cwd
          )
        ),
      nextCursor,
      backwardsCursor: null,
    };
  }

  private async readThread(params: unknown): Promise<Record<string, unknown>> {
    const parsed = parseThreadIdParams(params);
    const apiKey = this.requireApiKey();
    const live = this.liveThreads.get(parsed.threadId);
    if (live) {
      return {
        thread: projectAgentInfoToThread(live.info, live.cwd, live.turns),
      };
    }

    const workspace = this.resolveKnownThreadWorkspace(parsed.threadId, parsed.cwd);
    const { agent, messages, cwd, storeCwd } = await this.readPersistedThread(
      parsed.threadId,
      workspace,
      apiKey
    );
    this.rememberAgentCwd(agent, storeCwd, cwd);
    return {
      thread: projectAgentInfoToThread(agent, cwd, messagesToTurns(messages)),
    };
  }

  private listLoadedThreads(): Record<string, unknown> {
    return {
      data: [...this.liveThreads.keys()],
    };
  }

  private async startThread(params: unknown): Promise<Record<string, unknown>> {
    const parsed = parseThreadStartParams(params);
    const cwd = this.requireCwd(parsed.cwd);
    const model = this.requireModel(parsed.model);
    const apiKey = this.requireApiKey();
    const agent = await this.driver.createAgent({
      cwd,
      apiKey,
      name: parsed.name ?? undefined,
      model,
    });
    const now = Date.now();
    const info: CursorAgentInfo = {
      agentId: agent.agentId,
      name: parsed.name ?? '',
      summary: '',
      lastModified: now,
      createdAt: now,
      status: 'finished',
      runtime: this.runtime,
      cwd,
    };
    const state: LiveThreadState = {
      agent,
      info,
      cwd,
      storeCwd: cwd,
      model,
      turns: [],
      nameLocked: Boolean(parsed.name),
    };
    this.liveThreads.set(agent.agentId, state);
    this.knownThreadCwds.set(agent.agentId, cwd);
    this.knownThreadStoreCwds.set(agent.agentId, cwd);
    this.emit('thread/started', { threadId: agent.agentId });

    return {
      thread: projectAgentInfoToThread(info, cwd, state.turns),
    };
  }

  private async startTurn(params: unknown): Promise<Record<string, unknown>> {
    const parsed = parseTurnStartParams(params);
    this.requireApiKey();
    const state = await this.getOrResumeLiveThread(parsed.threadId, parsed.cwd);
    const model = this.requireTurnModel(parsed.model, state.model);
    const cursorPrompt = applyCursorModeToPrompt(parsed.prompt, parsed.collaborationMode);
    if (!state.nameLocked) {
      state.info.name = toPreview(parsed.prompt);
      state.nameLocked = true;
    }
    const run = await state.agent.send(
      await this.buildUserMessage(cursorPrompt, parsed.imagePaths),
      { model }
    );
    state.model = model;
    const turn: ThreadTurn = {
      id: run.id,
      status: 'in_progress',
      items: [
        {
          type: 'userMessage',
          id: `${run.id}-user`,
          content: this.buildUserThreadContent(parsed.prompt, parsed.imagePaths),
        },
      ],
    };
    state.turns.push(turn);
    state.activeRun = run;
    state.info.status = 'running';
    state.info.lastModified = Date.now();

    this.emit('turn/started', {
      threadId: parsed.threadId,
      turnId: run.id,
    });
    this.emit('thread/status/changed', {
      threadId: parsed.threadId,
      status: 'running',
    });

    void this.consumeRun(state, turn, run);

    return {
      turn: {
        id: run.id,
      },
    };
  }

  private async interruptTurn(params: unknown): Promise<Record<string, unknown>> {
    const parsed = parseThreadIdParams(params);
    const state = this.liveThreads.get(parsed.threadId);
    if (!state?.activeRun) {
      throw new Error(`no active Cursor run for thread: ${parsed.threadId}`);
    }

    await state.activeRun.cancel();
    state.info.status = 'finished';
    state.info.lastModified = Date.now();
    state.activeRun = undefined;
    this.emit('turn/completed', {
      threadId: parsed.threadId,
      turnId: null,
      status: 'cancelled',
    });
    this.emit('thread/status/changed', {
      threadId: parsed.threadId,
      status: 'idle',
    });
    return {};
  }

  private async listModels(): Promise<Record<string, unknown>> {
    const apiKey = this.requireApiKey();
    return {
      data: await this.driver.listModels({ apiKey }),
    };
  }

  private initialize(): Record<string, unknown> {
    return {
      serverInfo: {
        name: '@clawdex/cursor-app-server',
        title: 'Clawdex Cursor App Server',
        version: '0.1.0',
      },
      capabilities: {
        experimentalApi: true,
      },
    };
  }

  private async getOrResumeLiveThread(
    threadId: string,
    requestCwd: string | null = null
  ): Promise<LiveThreadState> {
    const live = this.liveThreads.get(threadId);
    if (live) {
      return live;
    }

    const workspace = this.resolveKnownThreadWorkspace(threadId, requestCwd);
    const apiKey = this.requireApiKey();
    const configuredModel = this.configuredModelOrUndefined();
    const { agent, info, messages, persistedModel, cwd, storeCwd } =
      await this.resumePersistedThread(threadId, workspace, apiKey, configuredModel);
    const state: LiveThreadState = {
      agent,
      info,
      cwd,
      storeCwd,
      model: agent.model ?? configuredModel ?? persistedModel,
      turns: messagesToTurns(messages),
      nameLocked: !isGenericCursorAgentName(info.name, info.agentId),
    };
    this.liveThreads.set(threadId, state);
    this.rememberAgentCwd(info, storeCwd, cwd);
    return state;
  }

  private async consumeRun(
    state: LiveThreadState,
    turn: ThreadTurn,
    run: CursorRunHandle
  ): Promise<void> {
    try {
      for await (const message of run.stream()) {
        this.applyStreamMessage(state.info.agentId, turn, run.id, message);
      }
      const result = await run.wait();
      await run.conversation();
      this.applyRunResult(state, turn, run, result);
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      turn.status = 'failed';
      turn.error = { message };
      state.info.status = 'error';
      state.info.lastModified = Date.now();
      state.activeRun = undefined;
      this.emit('turn/completed', {
        threadId: state.info.agentId,
        turnId: run.id,
        status: 'failed',
        error: { message },
      });
      this.emit('thread/status/changed', {
        threadId: state.info.agentId,
        status: 'failed',
        error: { message },
      });
    }
  }

  private applyStreamMessage(
    threadId: string,
    turn: ThreadTurn,
    runId: string,
    message: CursorStreamMessage
  ): void {
    if (message.type === 'assistant') {
      const text = readMessageText(message.message);
      if (!text.trim()) {
        return;
      }

      const item = this.findOrCreateTextItem(turn, 'agentMessage', `${runId}-assistant`);
      const merged = mergeStreamingText(item.text ?? '', text);
      item.text = merged.text;
      if (merged.delta) {
        this.emit('item/agentMessage/delta', {
          threadId,
          itemId: item.id,
          delta: merged.delta,
        });
      }
      return;
    }

    const item = streamMessageToThreadItem(message);
    if (!item) {
      return;
    }

    if (item.type === 'reasoning') {
      const textItem = this.findOrCreateTextItem(turn, 'reasoning', item.id);
      const merged = mergeStreamingText(textItem.text ?? '', item.text ?? '');
      textItem.text = merged.text;
      textItem.status = item.status;
      if (merged.delta) {
        this.emit('item/reasoning/textDelta', {
          threadId,
          itemId: textItem.id,
          delta: merged.delta,
        });
      }
      return;
    }

    if (item.type === 'toolCall') {
      const created = this.upsertToolCallItem(turn, item);
      if (created) {
        this.emit('item/started', {
          threadId,
          item,
        });
      }
      if (isTerminalToolCallStatus(item.status)) {
        this.emit('item/completed', {
          threadId,
          item,
        });
      }
    }
  }

  private applyRunResult(
    state: LiveThreadState,
    turn: ThreadTurn,
    run: CursorRunHandle,
    result: CursorRunResult
  ): void {
    if (result.result?.trim()) {
      const assistantItem = this.findAssistantItem(turn, run.id);
      if (assistantItem) {
        assistantItem.text = mergeFinalAssistantText(assistantItem.text ?? '', result.result);
      } else {
        turn.items.push({
          type: 'agentMessage',
          id: `${run.id}-assistant`,
          text: result.result,
        });
      }
    }
    const gitItem = runResultToGitThreadItem(run.id, result);
    if (gitItem) {
      this.upsertToolCallItem(turn, gitItem);
      this.emit('item/completed', {
        threadId: state.info.agentId,
        item: gitItem,
      });
    }
    turn.items = orderCompletedCursorTurnItems(turn.items);

    turn.status =
      result.status === 'finished'
        ? 'completed'
        : result.status === 'cancelled'
          ? 'cancelled'
          : 'failed';
    if (turn.status === 'failed' && !turn.error) {
      turn.error = { message: 'Cursor run failed' };
    }

    state.info.status = turn.status === 'failed' ? 'error' : 'finished';
    const assistantText = this.findAssistantItem(turn, run.id)?.text;
    state.info.summary = assistantText ? toPreview(assistantText) : state.info.summary;
    state.info.lastModified = Date.now();
    state.activeRun = undefined;

    this.emit('turn/completed', {
      threadId: state.info.agentId,
      turnId: run.id,
      status: turn.status === 'completed' ? 'completed' : turn.status,
      ...(turn.error ? { error: turn.error } : {}),
    });
    this.emit('thread/status/changed', {
      threadId: state.info.agentId,
      status: turn.status === 'failed' ? 'failed' : 'idle',
    });
  }

  private findOrCreateTextItem(
    turn: ThreadTurn,
    type: 'agentMessage' | 'reasoning',
    id: string
  ): ThreadItem {
    const existing = turn.items.find((item) => item.type === type && item.id === id);
    if (existing) {
      return existing;
    }

    const item: ThreadItem = {
      type,
      id,
      text: '',
    };
    turn.items.push(item);
    return item;
  }

  private upsertToolCallItem(turn: ThreadTurn, item: ThreadItem): boolean {
    const existing = turn.items.find(
      (entry) => entry.type === 'toolCall' && entry.id === item.id
    );
    if (!existing) {
      turn.items.push(item);
      return true;
    }

    existing.tool = item.tool;
    existing.status = item.status;
    existing.args = item.args;
    existing.result = item.result;
    existing.truncated = item.truncated;
    return false;
  }

  private findAssistantItem(turn: ThreadTurn, runId: string): ThreadItem | undefined {
    return (
      turn.items.find(
        (item) => item.type === 'agentMessage' && item.id === `${runId}-assistant`
      ) ?? [...turn.items].reverse().find((item) => item.type === 'agentMessage')
    );
  }

  private requireCwd(requestCwd: string | null): string {
    const cwd = normalizeString(requestCwd) ?? this.configuredCwd;
    if (!cwd) {
      throw new Error('CURSOR_WORKDIR or per-request cwd is required; no workspace fallback is allowed');
    }
    return cwd;
  }

  private resolveKnownThreadWorkspace(
    threadId: string,
    requestCwd: string | null | undefined
  ): ThreadWorkspace {
    const live = this.liveThreads.get(threadId);
    const cwd =
      live?.cwd ??
      normalizeString(requestCwd) ??
      this.knownThreadCwds.get(threadId) ??
      this.configuredCwd;
    if (!cwd) {
      throw new Error('CURSOR_WORKDIR or per-request cwd is required; no workspace fallback is allowed');
    }
    return {
      cwd,
      storeCwd:
        live?.storeCwd ??
        this.knownThreadStoreCwds.get(threadId) ??
        this.knownThreadCwds.get(threadId) ??
        cwd,
    };
  }

  private rememberAgentCwd(
    agent: CursorAgentInfo,
    storeCwd: string,
    effectiveCwd?: string
  ): void {
    const normalizedStoreCwd = normalizeString(storeCwd) ?? normalizeString(agent.cwd);
    const cwd =
      normalizeString(effectiveCwd) ?? normalizeString(agent.cwd) ?? normalizedStoreCwd;
    if (!cwd) {
      return;
    }
    this.knownThreadCwds.set(agent.agentId, cwd);
    if (normalizedStoreCwd) {
      this.knownThreadStoreCwds.set(agent.agentId, normalizedStoreCwd);
    }
  }

  private listKnownWorkspaceCwds(): string[] {
    const cwds = new Set<string>();
    if (this.configuredCwd) {
      cwds.add(this.configuredCwd);
    }
    for (const state of this.liveThreads.values()) {
      cwds.add(state.cwd);
    }
    for (const cwd of this.knownThreadCwds.values()) {
      cwds.add(cwd);
    }
    for (const cwd of this.knownThreadStoreCwds.values()) {
      cwds.add(cwd);
    }
    if (cwds.size === 0) {
      return [this.requireCwd(null)];
    }
    return [...cwds];
  }

  private async resolveAgentEffectiveCwd(
    agent: CursorAgentInfo,
    storeCwd: string,
    requestCwd: string | null
  ): Promise<string> {
    const agentCwd = normalizeString(agent.cwd);
    const transcriptCwd = await findCursorTranscriptWorkspaceCwd({
      agentId: agent.agentId,
      projectsDir: this.cursorProjectsDir,
      knownCwds: uniqueStrings([
        ...(requestCwd ? [requestCwd] : []),
        ...(agentCwd ? [agentCwd] : []),
        storeCwd,
        ...this.listKnownWorkspaceCwds(),
      ]),
    });
    return transcriptCwd ?? this.knownThreadCwds.get(agent.agentId) ?? agentCwd ?? storeCwd;
  }

  private async readPersistedThread(
    threadId: string,
    workspace: ThreadWorkspace,
    apiKey: string
  ): Promise<{
    agent: CursorAgentInfo;
    messages: CursorAgentMessage[];
    cwd: string;
    storeCwd: string;
  }> {
    let lastError: unknown;
    for (const storeCwd of this.candidateStoreCwds(threadId, workspace)) {
      try {
        const [rawAgent, messages] = await Promise.all([
          this.driver.getAgent(threadId, { cwd: storeCwd, apiKey }),
          this.driver.listMessages(threadId, { cwd: storeCwd, limit: 1000 }),
        ]);
        const cwd = await this.resolveAgentEffectiveCwd(rawAgent, storeCwd, workspace.cwd);
        return {
          agent: { ...rawAgent, cwd },
          messages,
          cwd,
          storeCwd,
        };
      } catch (error) {
        lastError = error;
      }
    }
    throw lastError instanceof Error ? lastError : new Error(String(lastError));
  }

  private async resumePersistedThread(
    threadId: string,
    workspace: ThreadWorkspace,
    apiKey: string,
    configuredModel: ModelSelection | undefined
  ): Promise<{
    agent: CursorAgentHandle;
    info: CursorAgentInfo;
    messages: CursorAgentMessage[];
    persistedModel: ModelSelection | undefined;
    cwd: string;
    storeCwd: string;
  }> {
    let lastError: unknown;
    for (const storeCwd of this.candidateStoreCwds(threadId, workspace)) {
      try {
        const [agent, rawInfo, messages, persistedModel] = await Promise.all([
          this.driver.resumeAgent(threadId, {
            cwd: workspace.cwd,
            ...(storeCwd === workspace.cwd ? {} : { storeCwd }),
            apiKey,
            model: configuredModel,
          }),
          this.driver.getAgent(threadId, { cwd: storeCwd, apiKey }),
          this.driver.listMessages(threadId, { cwd: storeCwd, limit: 1000 }),
          this.latestPersistedRunModel(threadId, storeCwd),
        ]);
        const cwd = await this.resolveAgentEffectiveCwd(rawInfo, storeCwd, workspace.cwd);
        return {
          agent,
          info: { ...rawInfo, cwd },
          messages,
          persistedModel,
          cwd,
          storeCwd,
        };
      } catch (error) {
        lastError = error;
      }
    }
    throw lastError instanceof Error ? lastError : new Error(String(lastError));
  }

  private candidateStoreCwds(threadId: string, workspace: ThreadWorkspace): string[] {
    return uniqueStrings([
      workspace.storeCwd,
      this.knownThreadStoreCwds.get(threadId),
      this.configuredCwd,
      workspace.cwd,
    ]);
  }

  private requireModel(requestModel: string | null): ModelSelection {
    const model = normalizeString(requestModel) ?? this.defaultModel;
    if (!model) {
      throw new Error('CURSOR_MODEL or per-request model is required for local Cursor agents');
    }
    return this.toModelSelection(model);
  }

  private requireTurnModel(
    requestModel: string | null,
    threadModel: ModelSelection | undefined
  ): ModelSelection {
    const model = normalizeString(requestModel);
    if (model) {
      return this.toModelSelection(model);
    }
    if (threadModel) {
      return threadModel;
    }
    const configured = this.configuredModelOrUndefined();
    if (configured) {
      return configured;
    }
    throw new Error(
      'CURSOR_MODEL, per-request model, or thread model is required for local Cursor agents'
    );
  }

  private configuredModelOrUndefined(): ModelSelection | undefined {
    return this.defaultModel ? this.toModelSelection(this.defaultModel) : undefined;
  }

  private async latestPersistedRunModel(
    threadId: string,
    cwd: string
  ): Promise<ModelSelection | undefined> {
    const result = await this.driver.listRuns(threadId, { cwd, limit: 50 });
    let latest: { index: number; createdAt: number; model: ModelSelection } | null = null;

    for (const [index, run] of result.items.entries()) {
      if (!run.model) {
        continue;
      }

      const createdAt =
        typeof run.createdAt === 'number' && Number.isFinite(run.createdAt)
          ? run.createdAt
          : index;
      if (
        !latest ||
        createdAt > latest.createdAt ||
        (createdAt === latest.createdAt && index > latest.index)
      ) {
        latest = {
          index,
          createdAt,
          model: run.model,
        };
      }
    }

    if (!latest) {
      return undefined;
    }
    return latest.model;
  }

  private requireApiKey(): string {
    if (!this.apiKey) {
      throw new Error('CURSOR_API_KEY is required for Cursor SDK operations');
    }
    return this.apiKey;
  }

  private async buildUserMessage(
    text: string,
    imagePaths: string[]
  ): Promise<{ text: string; images?: Array<{ data: string; mimeType: string }> }> {
    if (imagePaths.length === 0) {
      return { text };
    }

    const images = [];
    for (const imagePath of imagePaths) {
      const mimeType = inferImageMimeType(imagePath);
      const data = await readFile(imagePath, 'base64').catch((error: unknown) => {
        const message = error instanceof Error ? error.message : String(error);
        throw new Error(`failed to read Cursor local image ${imagePath}: ${message}`);
      });
      images.push({ data, mimeType });
    }

    return { text, images };
  }

  private buildUserThreadContent(text: string, imagePaths: string[]): ThreadItem['content'] {
    return [
      { type: 'text', text },
      ...imagePaths.map((path) => ({ type: 'localImage' as const, path })),
    ];
  }

  private toModelSelection(model: string): ModelSelection {
    return { id: model };
  }

  private emit(method: string, params: Record<string, unknown>): void {
    this.events.emit('notification', { method, params } satisfies AppServerNotification);
  }
}

export function createCursorAppServerFromEnv(
  env: NodeJS.ProcessEnv = process.env
): CursorAppServer {
  const options: CursorAppServerOptions = {
    runtime: 'local',
  };
  const cwd = normalizeString(env.CURSOR_WORKDIR);
  const apiKey = normalizeString(env.CURSOR_API_KEY);
  const defaultModel = normalizeString(env.CURSOR_MODEL);
  if (cwd) {
    options.cwd = cwd;
  }
  if (apiKey) {
    options.apiKey = apiKey;
  }
  if (defaultModel) {
    options.defaultModel = defaultModel;
  }
  return new CursorAppServer(options);
}

function normalizeString(value: string | null | undefined): string | null {
  const trimmed = value?.trim();
  return trimmed ? trimmed : null;
}

function applyCursorModeToPrompt(
  prompt: string,
  mode: 'default' | 'plan' | 'ask' | null
): string {
  if (mode === 'ask') {
    return [
      'Cursor mode: Ask. Answer questions and explain the codebase without modifying files or running mutating commands. If implementation is needed, describe the change instead of making it.',
      prompt,
    ].join('\n\n');
  }

  if (mode === 'plan') {
    return [
      'Cursor mode: Plan. Inspect the codebase and propose a concrete plan before implementation. Do not modify files or run mutating commands in this turn.',
      prompt,
    ].join('\n\n');
  }

  return prompt;
}

function compareCursorAgentsByUpdatedAtDesc(
  left: CursorAgentInfo,
  right: CursorAgentInfo
): number {
  const updatedDelta = right.lastModified - left.lastModified;
  return updatedDelta === 0 ? left.agentId.localeCompare(right.agentId) : updatedDelta;
}

function uniqueStrings(values: Array<string | null | undefined>): string[] {
  const unique = new Set<string>();
  for (const value of values) {
    const normalized = normalizeString(value);
    if (normalized) {
      unique.add(normalized);
    }
  }
  return [...unique];
}

function mergeStreamingText(current: string, incoming: string): { text: string; delta: string } {
  if (!incoming) {
    return { text: current, delta: '' };
  }
  if (!current) {
    return { text: incoming, delta: incoming };
  }
  if (incoming === current || current.endsWith(incoming)) {
    return { text: current, delta: '' };
  }
  if (incoming.startsWith(current)) {
    return {
      text: incoming,
      delta: incoming.slice(current.length),
    };
  }
  return {
    text: `${current}${incoming}`,
    delta: incoming,
  };
}

function mergeFinalAssistantText(current: string, finalText: string): string {
  if (!current.trim()) {
    return finalText;
  }
  if (current === finalText || current.startsWith(finalText)) {
    return current;
  }
  if (finalText.startsWith(current)) {
    return finalText;
  }
  return finalText;
}

function orderCompletedCursorTurnItems(items: ThreadItem[]): ThreadItem[] {
  return items
    .map((item, index) => ({ item, index }))
    .sort((left, right) => {
      const rankDelta = completedCursorTurnItemRank(left.item) - completedCursorTurnItemRank(right.item);
      return rankDelta === 0 ? left.index - right.index : rankDelta;
    })
    .map((entry) => entry.item);
}

function completedCursorTurnItemRank(item: ThreadItem): number {
  switch (item.type) {
    case 'userMessage':
      return 0;
    case 'toolCall':
      return 1;
    case 'reasoning':
      return 2;
    case 'agentMessage':
      return 3;
    default:
      return 2;
  }
}

function isTerminalToolCallStatus(status: string | undefined): boolean {
  const normalized = normalizeString(status)?.toLowerCase();
  return (
    normalized === 'completed' ||
    normalized === 'complete' ||
    normalized === 'error' ||
    normalized === 'failed'
  );
}

function runResultToGitThreadItem(runId: string, result: CursorRunResult): ThreadItem | null {
  const branches = result.git?.branches ?? [];
  if (branches.length === 0) {
    return null;
  }

  return {
    type: 'toolCall',
    id: `${runId}-git`,
    tool: 'git',
    status: 'completed',
    result: {
      branches,
    },
  };
}

function inferImageMimeType(path: string): string {
  switch (extname(path).toLowerCase()) {
    case '.png':
      return 'image/png';
    case '.jpg':
    case '.jpeg':
      return 'image/jpeg';
    case '.webp':
      return 'image/webp';
    case '.gif':
      return 'image/gif';
    default:
      throw new Error(`unsupported Cursor local image type: ${path}`);
  }
}

export function cursorStreamMessageText(message: CursorStreamMessage): string {
  return message.type === 'assistant' ? readMessageText(message.message) : '';
}
