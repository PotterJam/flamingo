function StatusMessage({ message = '' }) {
    return (
        <div className="text-base lg:text-lg text-gray-700 min-h-[1.5rem] text-center transition-all duration-200">
            {message || '\u00A0'}
        </div>
    );
}

export default StatusMessage;
