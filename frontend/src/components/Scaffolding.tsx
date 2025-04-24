import { FC, PropsWithChildren } from "react"

export const Scaffolding: FC<PropsWithChildren<{}>> = ({ children }) => {
    return (
        <main className="flex flex-col items-center justify-start min-h-screen bg-gray-100 p-4 font-sans">
            <h1 className="text-3xl font-bold mb-4 text-pink-400 flex-shrink-0">Flamin<span className="text-sky-400">go</span></h1>
            {children}
        </main>
    );
}
