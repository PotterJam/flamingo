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
        <div className="w-full max-w-sm mx-auto bg-white p-6 rounded-lg shadow-md text-center mt-10">
            <h2 className="text-xl font-semibold mb-4 text-gray-700">
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
                    className="w-full p-2 border border-gray-300 rounded mb-4 focus:outline-none focus:ring-2 focus:ring-blue-500 transition duration-150 ease-in-out"
                    aria-label="Enter your name"
                />
                <button
                    type="submit"
                    className="w-full px-4 py-2 bg-blue-500 text-black font-medium rounded hover:bg-blue-600 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:ring-offset-1 transition duration-150 ease-in-out disabled:opacity-50 disabled:cursor-not-allowed"
                    disabled={!name.trim()}
                >
                    Join Game
                </button>
            </form>
        </div>
    );
}

export default NameInput;
