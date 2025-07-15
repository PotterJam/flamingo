import { createEffect, For, Show } from 'solid-js';
import { store } from '../store';

function ChatBox() {
    let chatContainerRef: HTMLDivElement | undefined;

    createEffect(() => {
        store.gameState.messages.length;
        if (chatContainerRef) {
            chatContainerRef.scrollTop = chatContainerRef.scrollHeight;
        }
    });

    return (
        <div
            ref={chatContainerRef!}
            class="flex h-full flex-1 flex-col gap-1 overflow-y-auto p-2 text-sm"
        >
            <Show
                when={store.gameState.messages.length > 0}
                fallback={
                    <p class="m-auto text-gray-400 italic">
                        Chat messages will appear here...
                    </p>
                }
            >
                <For each={store.gameState.messages}>
                    {(msg) => (
                        <div
                            class={`break-words ${msg.isSystem ? 'text-gray-600 italic' : 'text-blue-950'}`}
                        >
                            <Show when={!msg.isSystem}>
                                <span class="mr-1 font-semibold">
                                    {msg.senderName}:
                                </span>
                            </Show>
                            {msg.message}
                        </div>
                    )}
                </For>
            </Show>
        </div>
    );
}

export default ChatBox;
