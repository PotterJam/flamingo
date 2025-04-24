import { FC, PropsWithChildren } from 'react';

export const Scaffolding: FC<PropsWithChildren<{}>> = ({ children }) => {
    return (
        <main className="flex min-h-screen flex-col items-center justify-start bg-gray-100 p-4 font-sans">
            <h1 className="mb-4 flex-shrink-0 text-3xl font-bold text-pink-400">
                Flamin<span className="text-sky-400">go</span>
            </h1>
            {children}
        </main>
    );
};
