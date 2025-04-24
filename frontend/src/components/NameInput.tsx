import { useState } from 'react';

function NameInput({ onNameSet }: { onNameSet: (name: string) => void }) {
    const [name, setName] = useState('');

    const handleSubmit = (e: any) => {
        e.preventDefault();
        const trimmedName = name.trim();
        if (trimmedName) {
            onNameSet(trimmedName);
        }
    };

    return (
        <div className="mx-auto mt-10 w-full max-w-sm rounded-lg bg-white p-6 text-center shadow-md">
            <h2 className="mb-4 text-xl font-semibold text-gray-700">
                Enter Your Name
            </h2>
            <form onSubmit={handleSubmit}>
                <input
                    type="text"
                    value={name}
                    onChange={(e) => setName(e.target.value)}
                    placeholder="Your Name"
                    maxLength={20}
                    required
                    className="mb-4 w-full rounded border border-gray-300 p-2 transition duration-150 ease-in-out focus:ring-2 focus:ring-blue-500 focus:outline-none"
                    aria-label="Enter your name"
                />
                <button
                    type="submit"
                    className="w-full rounded bg-blue-500 px-4 py-2 font-medium text-black transition duration-150 ease-in-out hover:bg-blue-600 focus:ring-2 focus:ring-blue-500 focus:ring-offset-1 focus:outline-none disabled:cursor-not-allowed disabled:opacity-50"
                    disabled={!name.trim()}
                >
                    Join Game
                </button>
            </form>
        </div>
    );
}

export default NameInput;
