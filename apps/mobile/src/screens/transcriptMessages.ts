import type { ChatMessage, ChatStatus } from '../api/types';

export interface ToolTranscriptGroup {
  kind: 'toolGroup';
  id: string;
  messages: ChatMessage[];
  compact: boolean;
}

export type TranscriptDisplayItem =
  | {
      kind: 'message';
      message: ChatMessage;
      renderKey: string;
    }
  | ToolTranscriptGroup;

/** Keeps each tool card bounded so very long runs don’t dominate the transcript. */
export const MAX_TOOL_MESSAGES_PER_TRANSCRIPT_GROUP = 14;

export function getVisibleTranscriptMessages(
  messages: ChatMessage[],
  showToolCalls: boolean
): ChatMessage[] {
  const filtered = messages.filter((msg) => {
    const text = msg.content || '';
    if (
      !showToolCalls &&
      msg.role === 'system' &&
      msg.systemKind !== 'tool' &&
      msg.systemKind !== 'subAgent' &&
      msg.systemKind !== 'reasoning' &&
      msg.systemKind !== 'compaction'
    ) {
      return false;
    }
    if (text.includes('FINAL_TASK_RESULT_JSON')) {
      return false;
    }
    if (text.includes('Current working directory is:')) {
      return false;
    }
    if (text.includes('You are operating in task worktree')) {
      return false;
    }
    if (msg.role === 'assistant' && !text.trim()) {
      return false;
    }
    return true;
  });

  return filtered;
}

export function buildTranscriptDisplayItems(
  messages: ChatMessage[],
  showToolCalls = true
): TranscriptDisplayItem[] {
  const items: TranscriptDisplayItem[] = [];
  let toolBuffer: ChatMessage[] = [];
  let userMessageOrdinal = 0;

  const flushToolBuffer = () => {
    if (toolBuffer.length === 0) {
      return;
    }

    items.push({
      kind: 'toolGroup',
      id: `tool-group-${toolBuffer[0]?.id ?? 'start'}-${toolBuffer[toolBuffer.length - 1]?.id ?? 'end'}`,
      messages: [...toolBuffer],
      compact: !showToolCalls,
    });

    toolBuffer = [];
  };

  for (const message of messages) {
    const isToolMessage = message.role === 'system' && message.systemKind === 'tool';
    if (isToolMessage) {
      toolBuffer.push(message);
      if (toolBuffer.length >= MAX_TOOL_MESSAGES_PER_TRANSCRIPT_GROUP) {
        flushToolBuffer();
      }
      continue;
    }

    flushToolBuffer();
    if (message.role === 'user') {
      userMessageOrdinal += 1;
    }
    items.push({
      kind: 'message',
      message,
      renderKey: buildTranscriptRenderKey(message, userMessageOrdinal),
    });
  }

  flushToolBuffer();
  return items;
}

function buildTranscriptRenderKey(message: ChatMessage, userMessageOrdinal: number): string {
  if (message.role !== 'user') {
    return message.id;
  }

  return `user-${String(userMessageOrdinal)}-${normalizeTranscriptKeyContent(message.content)}`;
}

function normalizeTranscriptKeyContent(value: string): string {
  return value.replace(/\r\n/g, '\n').trim();
}

export function syncVisibleSubAgentStatuses(
  messages: ChatMessage[],
  threadStatuses: ReadonlyMap<string, ChatStatus>
): ChatMessage[] {
  if (threadStatuses.size === 0) {
    return messages;
  }

  let nextMessages: ChatMessage[] | null = null;

  for (let index = 0; index < messages.length; index += 1) {
    const message = messages[index];
    const nextMessage = syncSubAgentMessageStatus(message, threadStatuses);

    if (!nextMessages) {
      if (nextMessage === message) {
        continue;
      }
      nextMessages = messages.slice(0, index);
    }

    nextMessages.push(nextMessage);
  }

  return nextMessages ?? messages;
}

function syncSubAgentMessageStatus(
  message: ChatMessage,
  threadStatuses: ReadonlyMap<string, ChatStatus>
): ChatMessage {
  if (message.systemKind !== 'subAgent' || !message.subAgentMeta) {
    return message;
  }

  const receiverThreadIds = message.subAgentMeta.receiverThreadIds ?? [];
  const nextStatus =
    receiverThreadIds
      .map((threadId) => threadStatuses.get(threadId))
      .find((status): status is ChatStatus => typeof status === 'string') ?? null;

  if (!nextStatus) {
    return message;
  }

  const nextContent = replaceSubAgentStatusLine(message.content, nextStatus);
  const previousStatus = message.subAgentMeta.agentStatus;
  if (nextContent === message.content && previousStatus === nextStatus) {
    return message;
  }

  return {
    ...message,
    content: nextContent,
    subAgentMeta: {
      ...message.subAgentMeta,
      agentStatus: nextStatus,
    },
  };
}

function replaceSubAgentStatusLine(content: string, status: ChatStatus): string {
  const statusLine = `Status: ${status}`;
  const lines = content.split('\n');
  let replaced = false;

  const nextLines = lines.map((line) => {
    if (!/^\s*Status:\s*/i.test(line)) {
      return line;
    }

    replaced = true;
    const indentation = line.match(/^\s*/)?.[0] ?? '';
    return `${indentation}${statusLine}`;
  });

  if (replaced) {
    return nextLines.join('\n');
  }

  return [...nextLines, `  ${statusLine}`].join('\n');
}
