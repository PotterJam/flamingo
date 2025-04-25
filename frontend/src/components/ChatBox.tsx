import { useRef, useEffect } from 'react';
import { useAppStore } from '../store';

function ChatBox() {
    const messages = useAppStore((s) => s.gameState.messages);
    const chatContainerRef = useRef<HTMLDivElement>(null);

    useEffect(() => {
        if (chatContainerRef.current) {
            chatContainerRef.current.scrollTop =
                chatContainerRef.current.scrollHeight;
        }
    }, [messages]);

    return (
        <div
            ref={chatContainerRef}
            className="flex h-full flex-col gap-1 overflow-y-auto rounded border border-gray-200 bg-gray-50 p-2 text-sm"
        >
            {messages.length > 0 ? (
                messages.map((msg, i) => (
                    <div
                        key={i}
                        className={`break-words ${msg.isSystem ? 'text-gray-600 italic' : 'text-gray-800'}`}
                    >
                        {!msg.isSystem && (
                            <span className="mr-1 font-semibold">
                                {msg.senderName}:
                            </span>
                        )}
                        {msg.message}
                    </div>
                ))
            ) : (
                <p className="m-auto text-gray-400 italic">
                    Chat messages will appear here...
                </p>
            )}
        </div>
    );
}

export default ChatBox;
