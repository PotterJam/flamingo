function WordDisplay({ word = '', blanks = '', length = 0 }) {
    return (
        <div className="flex min-h-[3rem] items-center justify-center rounded bg-gray-200 p-2 text-center text-2xl font-semibold tracking-widest select-none lg:text-3xl">
            {word ? (
                <span>{word}</span>
            ) : blanks ? (
                <>
                    <span className="mr-2">{blanks}</span>
                    <span className="text-sm text-gray-600">
                        ({length} letters)
                    </span>
                </>
            ) : (
                <span className="text-gray-400">&nbsp;</span>
            )}
        </div>
    );
}

export default WordDisplay;
