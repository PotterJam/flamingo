import { useRef, useEffect } from 'react';
import { ChatMessage } from '../messages';

function ChatBox({ messages = [] }: { messages: ChatMessage[] }) {
    const chatContainerRef = useRef<HTMLDivElement>(null);

    // Effect to scroll to bottom when messages change
    useEffect(() => {
        if (chatContainerRef.current) {
            chatContainerRef.current.scrollTop = chatContainerRef.current.scrollHeight;
        }
    }, [messages]); // Dependency array includes messages

    return (
        <div
            ref={chatContainerRef}
            className="h-full border border-gray-200 rounded p-2 overflow-y-auto bg-gray-50 flex flex-col gap-1 text-sm"
        >
            {messages.length > 0 ? (
                messages.map((msg, i) => (
                    <div
                        // Using index as key is okay for chat if messages aren't reordered/deleted often
                        key={i}
                        className={`break-words ${msg.isSystem ? 'italic text-gray-600' : 'text-gray-800'}`}
                    >
                        {!msg.isSystem && (
                            <span className="font-semibold mr-1">{msg.senderName}:</span>
                        )}
                        {msg.message}
                    </div>
                ))
            ) : (
                <p className="text-gray-400 m-auto italic">Chat messages will appear here...</p>
            )}
        </div>
    );
}

export default ChatBox;
